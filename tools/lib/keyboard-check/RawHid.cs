// Raw HID access for the VIA / Vial interface (usage page 0xFF60, usage 0x61).
// Loaded by tools/lib/keyboard-check/rawhid.ps1 with Add-Type.
// Must stay C# 5 compatible (Windows PowerShell 5.1 compiles it with the .NET Framework compiler)
// and ASCII only.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

public static class KcRawHid
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("hid.dll", SetLastError = true)]
    static extern bool HidD_GetProductString(SafeFileHandle handle, byte[] buffer, int length);

    const uint GENERIC_READ = 0x80000000;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ_WRITE = 3;
    const uint OPEN_EXISTING = 3;
    const uint FILE_FLAG_OVERLAPPED = 0x40000000;
    const int REPORT_SIZE = 32;

    static SafeFileHandle Open(string path, uint access)
    {
        SafeFileHandle handle = CreateFile(path, access, FILE_SHARE_READ_WRITE, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, IntPtr.Zero);
        if (handle.IsInvalid)
        {
            throw new IOException("cannot open the raw HID interface (Win32 error " + Marshal.GetLastWin32Error() + ")");
        }
        return handle;
    }

    // Sends a command as a 32-byte output report (report ID 0, zero padded) and returns the 32-byte
    // response. A fresh handle is opened for every query, so reports queued before the query are never
    // mistaken for the response.
    //   echoLen > 0: the response must start with the first echoLen bytes of the command
    //                (VIA echoes the request), or with 0xFF (id_unhandled).
    //   echoLen = 0: the first report after the write is the response (Vial 0xFE commands do not echo).
    public static byte[] Query(string path, byte[] command, int timeoutMs, int echoLen)
    {
        if (command == null || command.Length == 0 || command.Length > REPORT_SIZE)
        {
            throw new ArgumentException("command must be 1 to 32 bytes");
        }
        using (SafeFileHandle handle = Open(path, GENERIC_READ | GENERIC_WRITE))
        using (FileStream stream = new FileStream(handle, FileAccess.ReadWrite, 1, true))
        {
            byte[] report = new byte[REPORT_SIZE + 1];
            Array.Copy(command, 0, report, 1, command.Length);
            stream.Write(report, 0, report.Length);
            stream.Flush();
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            for (int i = 0; i < 16; i++)
            {
                int remaining = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
                if (remaining <= 0)
                {
                    break;
                }
                byte[] input = new byte[REPORT_SIZE + 1];
                Task<int> read = stream.ReadAsync(input, 0, input.Length);
                if (!read.Wait(remaining))
                {
                    break;
                }
                bool match = echoLen <= 0 || input[1] == 0xFF;
                if (!match)
                {
                    match = true;
                    for (int j = 0; j < echoLen && j < command.Length; j++)
                    {
                        if (input[1 + j] != command[j])
                        {
                            match = false;
                            break;
                        }
                    }
                }
                if (match)
                {
                    byte[] response = new byte[REPORT_SIZE];
                    Array.Copy(input, 1, response, 0, REPORT_SIZE);
                    return response;
                }
            }
            throw new TimeoutException("no response from the raw HID interface");
        }
    }

    // Listens without sending anything and returns the number of input reports received.
    // A non-zero count means another application (VIA / Vial / Remap) is talking to the device.
    public static int CountTraffic(string path, int listenMs)
    {
        using (SafeFileHandle handle = Open(path, GENERIC_READ | GENERIC_WRITE))
        using (FileStream stream = new FileStream(handle, FileAccess.ReadWrite, 1, true))
        {
            int count = 0;
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(listenMs);
            while (true)
            {
                int remaining = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
                if (remaining <= 0)
                {
                    return count;
                }
                byte[] input = new byte[REPORT_SIZE + 1];
                Task<int> read = stream.ReadAsync(input, 0, input.Length);
                if (!read.Wait(remaining))
                {
                    return count;
                }
                count++;
            }
        }
    }

    // USB product string of the HID interface (e.g. "Keyball39"). Empty when it cannot be read.
    public static string GetProductString(string path)
    {
        try
        {
            using (SafeFileHandle handle = Open(path, 0))
            {
                byte[] buffer = new byte[256];
                if (!HidD_GetProductString(handle, buffer, buffer.Length))
                {
                    return "";
                }
                string s = Encoding.Unicode.GetString(buffer);
                int end = s.IndexOf('\0');
                return end >= 0 ? s.Substring(0, end) : s;
            }
        }
        catch (IOException)
        {
            return "";
        }
    }
}
