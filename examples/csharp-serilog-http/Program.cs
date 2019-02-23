using System;
using Serilog;
using Serilog.Context;

namespace SerilogHttp
{
    class Program
    {
        static void Main(string[] args)
        {
            var application = "csharp-serilog-http/1.0";

            Log.Logger = new LoggerConfiguration()
                .MinimumLevel.Debug()
                .Enrich.WithProperty("Application", application)
                .Enrich.FromLogContext()
                .WriteTo.Http("http://localhost:8080")
                .CreateLogger();

            var log = Log.ForContext<Program>();

            log.Information("Begin");

            var traceId = Guid.NewGuid().ToString("N");

            using (LogContext.PushProperty("TraceId", traceId))
            {
                var a = 10;
                var b = 0;

                try
                {
                    log.Debug("Dividing {A} by {B}", a, b);
                    Console.WriteLine(a / b);
                }
                catch (Exception ex)
                {
                    log.Error(ex, "Something went wrong with the division");
                }
            }

            log.Information("End");

            Log.CloseAndFlush();
        }
    }
}
