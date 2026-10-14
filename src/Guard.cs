using System;
using System.IO;
using System.Linq;
using System.Threading;
using HidSharp;

namespace ThermoSaver
{
    public sealed class FanReading
    {
        public DateTime TimestampUtc { get; }
        public int Rpm { get; }
        public bool Stopped { get; }
        public FanReading(DateTime timestampUtc, int rpm, bool stopped)
        { TimestampUtc = timestampUtc; Rpm = rpm; Stopped = stopped; }
    }

    public static class ReportParser
    {
        public static FanReading Parse(byte[] bytes, int count, DateTime utcNow)
        {
            // BS3 Pro HID heartbeat: report ID, header, 13-byte body, additive checksum.
            if (count < 17 || bytes.Length < count || bytes[0] != 1 ||
                bytes[1] != 0x5a || bytes[2] != 0xa5 || bytes[3] != 0xef || bytes[4] != 13)
                return null;
            int checksum = 0;
            for (int i = 0; i < 16; i++) checksum = (checksum + bytes[i]) & 255;
            if (checksum != bytes[16]) return null;
            int rpm = bytes[8] | (bytes[9] << 8);
            if (rpm > 10000) return null;
            return new FanReading(utcNow, rpm, (bytes[5] & 1) != 0);
        }
    }

    public sealed class Decision
    {
        public bool Armed { get; }
        public bool CpuValid { get; }
        public bool FanKnown { get; }
        public bool FanRunning { get; }
        public int Threshold { get; }
        public bool Hibernate { get; }
        public Decision(bool armed, bool valid, bool known, bool running, int threshold, bool hibernate)
        { Armed = armed; CpuValid = valid; FanKnown = known; FanRunning = running; Threshold = threshold; Hibernate = hibernate; }
    }

    public static class Policy
    {
        public static Decision Evaluate(double? cpu, FanReading fan, DateTime now, DateTime armedAfter,
            int stoppedThreshold = 90, int runningThreshold = 95)
        {
            bool armed = now >= armedAfter;
            bool valid = cpu.HasValue && !double.IsNaN(cpu.Value) && !double.IsInfinity(cpu.Value)
                && cpu.Value >= 10 && cpu.Value <= 125;
            bool known = fan != null && fan.TimestampUtc <= now && (now - fan.TimestampUtc).TotalSeconds <= 5;
            bool running = known && !fan.Stopped && fan.Rpm > 0;
            int threshold = running ? runningThreshold : stoppedThreshold;
            return new Decision(armed, valid, known, running, threshold, armed && valid && cpu.Value > threshold);
        }
    }

    public sealed class AlertGate
    {
        readonly double sustainedSeconds;
        DateTime lastObservation;
        int observedThreshold;
        public DateTime OverThresholdSinceUtc { get; private set; }
        public AlertGate() : this(10) { }
        public AlertGate(double sustainedSeconds) { this.sustainedSeconds = sustainedSeconds; }
        public string AlertId { get; private set; }
        public DateTime DeadlineUtc { get; private set; }
        public DateTime RetryAfterUtc { get; private set; }
        public void Restore(string alertId, DateTime deadline, DateTime retryAfter)
        {
            AlertId = string.IsNullOrEmpty(alertId) ? null : alertId;
            DeadlineUtc = deadline.ToUniversalTime();
            RetryAfterUtc = retryAfter.ToUniversalTime();
        }
        public string Advance(Decision decision, DateTime now, string action = null, string actionId = null)
        {
            if (sustainedSeconds > 0 && ((lastObservation != DateTime.MinValue && (now - lastObservation).TotalSeconds > 3) ||
                (observedThreshold != 0 && observedThreshold != decision.Threshold)))
            {
                OverThresholdSinceUtc = DateTime.MinValue;
                AlertId = null;
            }
            lastObservation = now;
            observedThreshold = decision.Threshold;
            if (!decision.Armed || !decision.CpuValid)
            {
                OverThresholdSinceUtc = DateTime.MinValue;
                AlertId = null;
                return "clear";
            }
            if (!decision.Hibernate)
            {
                OverThresholdSinceUtc = DateTime.MinValue;
                AlertId = null;
                RetryAfterUtc = DateTime.MinValue;
                return "clear";
            }
            if (OverThresholdSinceUtc == DateTime.MinValue) OverThresholdSinceUtc = now;
            if ((now - OverThresholdSinceUtc).TotalSeconds < sustainedSeconds) return "qualifying";
            if (AlertId != null && actionId == AlertId)
            {
                if (action == "cancel")
                {
                    AlertId = null;
                    RetryAfterUtc = now.AddSeconds(60);
                    return "cancelled";
                }
                if (action == "hibernate")
                {
                    AlertId = null;
                    RetryAfterUtc = now.AddSeconds(60);
                    return "hibernate";
                }
            }
            if (AlertId != null && now >= DeadlineUtc)
            {
                AlertId = null;
                RetryAfterUtc = now.AddSeconds(60);
                return "hibernate";
            }
            if (AlertId == null && now >= RetryAfterUtc)
            {
                AlertId = Guid.NewGuid().ToString("N");
                DeadlineUtc = now.AddSeconds(20);
                return "alert";
            }
            return AlertId != null ? "countdown" : "cooldown";
        }
    }

    public sealed class FanReader : IDisposable
    {
        readonly string mac;
        readonly object gate = new object();
        readonly ManualResetEvent stop = new ManualResetEvent(false);
        readonly Thread thread;
        FanReading latest;
        HidStream stream;
        string error;
        public FanReader(string mac)
        {
            this.mac = mac.ToLowerInvariant();
            thread = new Thread(ReadLoop) { IsBackground = true, Name = "Flydigi RPM reader" };
            thread.Start();
        }
        public FanReading Current { get { lock (gate) return latest; } }
        public string Error { get { lock (gate) return error; } }
        void ReadLoop()
        {
            while (!stop.WaitOne(0))
            {
                HidStream opened = null;
                try
                {
                    var device = DeviceList.Local.GetHidDevices(0x37d7, 0x1004)
                        .FirstOrDefault(d => d.DevicePath.ToLowerInvariant().Contains(mac));
                    if (device == null || !device.TryOpen(out opened))
                        throw new IOException("Flydigi HID unavailable");
                    lock (gate) stream = opened;
                    opened.ReadTimeout = 1000;
                    var bytes = new byte[device.GetMaxInputReportLength()];
                    var lastReport = DateTime.UtcNow;
                    while (!stop.WaitOne(0))
                    {
                        try
                        {
                            int count = opened.Read(bytes, 0, bytes.Length);
                            var parsed = ReportParser.Parse(bytes, count, DateTime.UtcNow);
                            if (parsed != null)
                            {
                                lock (gate) { latest = parsed; error = null; }
                                lastReport = parsed.TimestampUtc;
                            }
                        }
                        catch (TimeoutException) { }
                        if ((DateTime.UtcNow - lastReport).TotalSeconds > 15)
                            throw new IOException("No current Flydigi RPM reports");
                    }
                }
                catch (Exception ex) { lock (gate) { error = ex.Message; latest = null; } }
                finally
                {
                    lock (gate) stream = null;
                    if (opened != null) opened.Dispose();
                }
                stop.WaitOne(2000);
            }
        }
        public void Dispose()
        {
            stop.Set();
            lock (gate) { if (stream != null) stream.Dispose(); }
            if (thread.Join(5000)) stop.Dispose();
        }
    }
}
