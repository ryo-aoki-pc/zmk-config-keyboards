// Runs one flashing step of tools/flash.ps1 (flash-uf2.ps1 / flash-keyball.ps1 in a child powershell.exe)
// with its output redirected. The output is read on background threads and queued line by line; the
// PowerShell thread takes the lines with TakeLines() while the window (KcFlashForm) stays responsive.
// The child is put in a Job Object that kills the whole process tree when the job is closed, so Kill(),
// Dispose() and the end of the tool also end grandchildren such as avrdude.exe (a stray child would
// otherwise keep waiting for a bootloader drive and write an old firmware to it later).
// Loaded by tools/flash.ps1 with Add-Type. It shares no types with InputTestForm.cs, so it is a file of
// its own. Must stay C# 5 compatible (Windows PowerShell 5.1 compiles it with the .NET Framework
// compiler and treats warnings as errors) and ASCII only.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// One line of output. Partial: the line ended with a bare CR (a progress line that the next line
// replaces, as avrdude draws its progress bar).
public sealed class KcChildLine
{
    public string Text;
    public bool IsError;
    public bool Partial;
}

public sealed class KcChildProcess : IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    public struct JobBasicLimits
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JobIoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JobExtendedLimits
    {
        public JobBasicLimits BasicLimitInformation;
        public JobIoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JobExtendedLimits info, int length);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateJobObject(IntPtr job, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    const int JobObjectExtendedLimitInformation = 9;
    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
    // After the process has exited, how long to wait for the end of its output (a grandchild may still
    // hold the pipe open).
    const int DrainMs = 2000;

    readonly object sync = new object();
    readonly List<KcChildLine> lines = new List<KcChildLine>();
    readonly Process process;
    readonly Thread outThread;
    readonly Thread errThread;
    IntPtr job = IntPtr.Zero;
    volatile bool killed;
    bool disposed;
    DateTime exitSeen = DateTime.MinValue;

    KcChildProcess(Process p)
    {
        process = p;
        outThread = StartReader(p.StandardOutput, false, "flash-stdout");
        errThread = StartReader(p.StandardError, true, "flash-stderr");
    }

    // Starts fileName with arguments. codePage is the encoding of the child's output (65001 = UTF-8).
    public static KcChildProcess Start(string fileName, string arguments, string workingDirectory, int codePage)
    {
        ProcessStartInfo psi = new ProcessStartInfo(fileName, arguments ?? "");
        psi.UseShellExecute = false;
        // A console of its own (hidden): the child changes its output encoding, which must not change
        // the code page of the user's console.
        psi.CreateNoWindow = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        psi.RedirectStandardInput = true;
        Encoding encoding = codePage == 65001 ? (Encoding)new UTF8Encoding(false) : Encoding.GetEncoding(codePage);
        psi.StandardOutputEncoding = encoding;
        psi.StandardErrorEncoding = encoding;
        if (!string.IsNullOrEmpty(workingDirectory))
        {
            psi.WorkingDirectory = workingDirectory;
        }
        Process p = new Process();
        p.StartInfo = psi;
        p.Start();
        KcChildProcess child = new KcChildProcess(p);
        child.AttachJob();
        try
        {
            // nothing is typed into the child: a prompt fails at once instead of waiting
            p.StandardInput.Close();
        }
        catch (IOException)
        {
        }
        return child;
    }

    public int Id { get { return process.Id; } }

    // True when the process is in the Job Object (Kill also ends its children).
    public bool InJob { get { return job != IntPtr.Zero; } }

    public bool Killed { get { return killed; } }

    // True once the process has exited and its output has been read (or DrainMs after the exit).
    public bool HasExited
    {
        get
        {
            if (!process.HasExited)
            {
                return false;
            }
            if (!outThread.IsAlive && !errThread.IsAlive)
            {
                return true;
            }
            lock (sync)
            {
                if (exitSeen == DateTime.MinValue)
                {
                    exitSeen = DateTime.UtcNow;
                }
                return (DateTime.UtcNow - exitSeen).TotalMilliseconds >= DrainMs;
            }
        }
    }

    public int ExitCode { get { return process.HasExited ? process.ExitCode : -1; } }

    public KcChildLine[] TakeLines()
    {
        lock (sync)
        {
            KcChildLine[] a = lines.ToArray();
            lines.Clear();
            return a;
        }
    }

    // Waits until HasExited; false on timeout.
    public bool WaitExit(int timeoutMs)
    {
        DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (!HasExited)
        {
            if (DateTime.UtcNow >= deadline)
            {
                return false;
            }
            Thread.Sleep(20);
        }
        return true;
    }

    // Ends the process and its children (idempotent).
    public void Kill()
    {
        if (process.HasExited && job == IntPtr.Zero)
        {
            return;
        }
        killed = true;
        if (job != IntPtr.Zero)
        {
            TerminateJobObject(job, 1);
        }
        else
        {
            KillTree();
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        if (!process.HasExited)
        {
            Kill();
        }
        if (job != IntPtr.Zero)
        {
            // closing the last handle also ends any process left in the job
            CloseHandle(job);
            job = IntPtr.Zero;
        }
        process.Dispose();
    }

    // ---- internals ----

    void AttachJob()
    {
        IntPtr h;
        try
        {
            h = CreateJobObject(IntPtr.Zero, null);
        }
        catch (Exception)
        {
            // no kernel32 (the tests also run on Linux, where loading it throws): Kill() ends the
            // process (and taskkill its tree) instead
            return;
        }
        if (h == IntPtr.Zero)
        {
            return;
        }
        JobExtendedLimits info = new JobExtendedLimits();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        bool ok = SetInformationJobObject(h, JobObjectExtendedLimitInformation, ref info, Marshal.SizeOf(typeof(JobExtendedLimits)));
        if (ok)
        {
            try
            {
                ok = AssignProcessToJobObject(h, process.Handle);
            }
            catch (InvalidOperationException)
            {
                ok = false;
            }
        }
        if (!ok)
        {
            CloseHandle(h);
            return;
        }
        job = h;
    }

    // Without a job: taskkill ends the process tree.
    void KillTree()
    {
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo("taskkill.exe", "/PID " + process.Id + " /T /F");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            using (Process p = Process.Start(psi))
            {
                p.WaitForExit(5000);
            }
        }
        catch (Exception)
        {
            try
            {
                process.Kill();
            }
            catch (Exception)
            {
                // already gone
            }
        }
    }

    Thread StartReader(StreamReader reader, bool isError, string name)
    {
        Thread t = new Thread(delegate() { ReadLoop(reader, isError); });
        t.IsBackground = true;
        t.Name = name;
        t.Start();
        return t;
    }

    void ReadLoop(StreamReader reader, bool isError)
    {
        char[] buffer = new char[4096];
        StringBuilder line = new StringBuilder();
        bool crPending = false;
        bool first = true;
        while (true)
        {
            int n;
            try
            {
                n = reader.Read(buffer, 0, buffer.Length);
            }
            catch (Exception)
            {
                break;
            }
            if (n <= 0)
            {
                break;
            }
            for (int i = 0; i < n; i++)
            {
                char c = buffer[i];
                if (first)
                {
                    first = false;
                    if (c == '\uFEFF')
                    {
                        continue;
                    }
                }
                if (crPending)
                {
                    crPending = false;
                    if (c == '\n')
                    {
                        Emit(line, isError, false);
                        continue;
                    }
                    Emit(line, isError, true);
                }
                if (c == '\r')
                {
                    crPending = true;
                }
                else if (c == '\n')
                {
                    Emit(line, isError, false);
                }
                else
                {
                    line.Append(c);
                }
            }
        }
        if (crPending || line.Length > 0)
        {
            Emit(line, isError, false);
        }
    }

    void Emit(StringBuilder line, bool isError, bool partial)
    {
        if (partial && line.Length == 0)
        {
            return;
        }
        KcChildLine l = new KcChildLine();
        l.Text = line.ToString();
        l.IsError = isError;
        l.Partial = partial;
        line.Length = 0;
        lock (sync)
        {
            lines.Add(l);
        }
    }
}
