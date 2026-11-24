// PCSDKUI 替身：接管 QuickSDK 的命名管道，直接返回本地登录成功。
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;

internal static class Program
{
    private static readonly string LogPath =
        Environment.GetEnvironmentVariable("PCSDKUI_STUB_LOG") ??
        Path.Combine(Path.GetTempPath(), "pc-sdkui-stub.log");

    private static readonly object Gate = new object();

    private static void Log(string message)
    {
        try
        {
            lock (Gate)
            {
                File.AppendAllText(LogPath, DateTime.Now.ToString("HH:mm:ss.fff") + " " + message + "\r\n", Encoding.UTF8);
            }
        }
        catch { }
    }

    private static string Uid()
    {
        string uid = Environment.GetEnvironmentVariable("LOLO_SDK_UID");
        if (string.IsNullOrEmpty(uid)) uid = "1000000";
        foreach (char c in uid) if (c < '0' || c > '9') return "1000000";
        return uid;
    }

    private static string LoginMessage(string uid)
    {
        return "{\"action\":\"loginSuccess\",\"params\":{\"authToken\":\"local-session\",\"userToken\":\"local-session\",\"uid\":\"" +
               uid + "\",\"username\":\"UID " + uid + "\",\"timeleft\":\"-1\"}}";
    }

    private static void Send(Stream s, string text)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(text);
        try { s.Write(bytes, 0, bytes.Length); s.Flush(); Log("SENT " + text); }
        catch (Exception ex) { Log("SEND-ERR " + ex.Message); }
    }

    private static List<string> Pipes()
    {
        List<string> list = new List<string>();
        try
        {
            foreach (string full in Directory.GetFiles(@"\\.\pipe\"))
            {
                string n = full.Substring(full.LastIndexOf('\\') + 1);
                if (n.StartsWith("quickpc", StringComparison.OrdinalIgnoreCase) &&
                    !n.StartsWith("quickpcUnityUI", StringComparison.OrdinalIgnoreCase))
                    list.Add(n);
            }
        }
        catch (Exception ex) { Log("enum-err " + ex.Message); }
        return list;
    }

    private static bool Session(string name, string mode, string uid)
    {
        NamedPipeClientStream pipe = null;
        try
        {
            pipe = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
            pipe.Connect(1500);
            Log("connected " + name + " mode=" + mode);

            if (mode == "init")
            {
                Send(pipe, "{\"action\":\"init\",\"params\":{}}");
            }
            else
            {
                Thread.Sleep(100);
                Send(pipe, LoginMessage(uid));
            }

            byte[] buf = new byte[8192];
            DateTime deadline = DateTime.UtcNow.AddSeconds(6);
            while (DateTime.UtcNow < deadline)
            {
                IAsyncResult ar = pipe.BeginRead(buf, 0, buf.Length, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(1000)) continue;
                int n = pipe.EndRead(ar);
                if (n <= 0) { Log("EOF mode=" + mode); return mode != "init"; }
                Log("RECV " + Encoding.UTF8.GetString(buf, 0, n).Replace("\r", "\\r").Replace("\n", "\\n"));
                if (mode != "init") return true;
            }
            return mode != "init";
        }
        catch (Exception ex)
        {
            Log("SESSION-ERR " + mode + " " + ex.GetType().Name + ": " + ex.Message);
            return false;
        }
        finally
        {
            if (pipe != null) pipe.Dispose();
        }
    }

    private static int Main(string[] args)
    {
        Log("START pid=" + System.Diagnostics.Process.GetCurrentProcess().Id + " args=" + string.Join(" | ", args));
        string uid = Uid();
        DateTime overall = DateTime.UtcNow.AddSeconds(90);
        int round = 0;

        while (DateTime.UtcNow < overall)
        {
            round++;
            foreach (string name in Pipes())
            {
                Session(name, "init", uid);
                Thread.Sleep(150);
                if (Session(name, "login", uid))
                {
                    Log("login accepted; exiting");
                    Thread.Sleep(800);
                    return 0;
                }
            }
            if (round >= 30) break;
            Thread.Sleep(500);
        }

        Log("give up");
        return 1;
    }
}
