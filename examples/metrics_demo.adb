--  Runnable demo for prometheus: register a counter and a histogram,
--  record observations, print the text exposition that a Prometheus
--  server would scrape.
with Ada.Text_IO;
with Prometheus; use Prometheus;

procedure Metrics_Demo is
   use Ada.Text_IO;

   Reg  : Registry_Type;
   Reqs : Counter_Access;
   Dur  : Histogram_Access;
begin
   Reqs := Reg.Register_Counter ("http_requests_total",
                                 "Total HTTP requests");
   Dur  := Reg.Register_Histogram ("request_duration_seconds",
                                   "Request duration in seconds");

   Inc (Reqs.all);
   Inc (Reqs.all, 41.0);

   Observe (Dur.all, 0.042);
   Observe (Dur.all, 0.7);
   Observe (Dur.all, 3.1);

   --  What a Prometheus server scrapes (/metrics):
   Put_Line (Reg.Collect);
end Metrics_Demo;
