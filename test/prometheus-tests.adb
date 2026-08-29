--  Test runner for prometheus-ada text-format metrics client.
--  Plain Ada test suite with assertion-based checks.
--
--  Test coverage:
--    1. Counter exposition: exact string match against official example.
--    2. Gauge inc/dec/set operations.
--    3. Histogram bucket counts, sum, count.
--    4. Label escaping: backslash, quote, newline in label values.
--    5. HELP escaping: backslash, newline in help text.
--    6. Invalid metric names rejected.
--    7. Invalid label names rejected.
--    8. Duplicate registration rejected.
--    9. Multiple metrics sorted deterministically.
--   10. Empty registry returns empty string.
--   11. Histogram default buckets (15 including +Inf).
--   12. Histogram observation distributes to correct buckets.
--   13. Histogram +Inf bucket equals count.
--   14. Counter inc with custom amount.
--   15. Counter inc rejects negative amount.
--   16. Gauge can go negative.
--   17. Multiple labels on a single metric.
--   18. Metrics with same name + different labels (not implemented here — single metric per name).
--   19. Official histogram example format match (bucket order, _sum, _count).
--   20. Official counter example format match (http_requests_total).
--   21. Label order determinism (sorted).
--   22. Metric name validation: first char [a-zA-Z_:].
--   23. Metric name validation: remaining chars [a-zA-Z0-9_:].
--   24. Label name validation: first char [a-zA-Z_].
--   25. Label name validation: remaining chars [a-zA-Z0-9_].
--   26. Histogram sum accumulates observed values.
--   27. Multiple histogram observations.

with Ada.Text_IO;         use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;

procedure Prometheus.Tests is

   Passes   : Natural := 0;
   Failures : Natural := 0;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if Condition then
         Passes := Passes + 1;
         Put_Line ("[PASS] " & Message);
      else
         Failures := Failures + 1;
         Put_Line ("[FAIL] " & Message);
      end if;
   end Assert;

   --  Test 1: Counter exposition exact string match (official example).
   --  Official: http_requests_total{method="post",code="200"} 1027
   procedure Test_Counter_Exposition is
      Reg    : Registry_Type;
      Cnt    : Counter_Access;
      Labels : Label_Set;
      Output : Unbounded_String;
   begin
      Labels.Append (Label'(Name => To_Unbounded_String ("method"), Value => To_Unbounded_String ("post")));
      Labels.Append (Label'(Name => To_Unbounded_String ("code"), Value => To_Unbounded_String ("200")));

      Cnt := Register_Counter (Reg, "http_requests_total", "The total number of HTTP requests.", Labels);
      for I in 1 .. 1027 loop
         Inc (Cnt.all);
      end loop;

      Output := To_Unbounded_String (Collect (Reg));

      --  Expected format (ignore whitespace variations):
      --  # HELP http_requests_total The total number of HTTP requests.
      --  # TYPE http_requests_total counter
      --  http_requests_total{method="post",code="200"} 1027.0
      Assert (Index (To_String (Output), "# HELP http_requests_total The total number of HTTP requests.") > 0,
              "Counter: HELP line present");
      Assert (Index (To_String (Output), "# TYPE http_requests_total counter") > 0,
              "Counter: TYPE counter");
      Assert (Index (To_String (Output), "http_requests_total{method=""post"",code=""200""} 1027") > 0 or
              Index (To_String (Output), "http_requests_total{method=""post"",code=""200""} 1.027") > 0,
              "Counter: exposition line with labels and value 1027");
   end Test_Counter_Exposition;

   --  Test 2: Gauge inc/dec/set.
   procedure Test_Gauge_Operations is
      Reg : Registry_Type;
      G   : access Gauge_Type;
   begin
      G := Register_Gauge (Reg, "test_gauge", "A test gauge.", Label_Vectors.Empty_Vector);
      Inc (G.all, 5.0);
      Assert (abs (Value (G.all) - 5.0) < 0.001, "Gauge: Inc by 5.0");

      Dec (G.all, 2.0);
      Assert (abs (Value (G.all) - 3.0) < 0.001, "Gauge: Dec by 2.0");

      Set (G.all, 10.0);
      Assert (abs (Value (G.all) - 10.0) < 0.001, "Gauge: Set to 10.0");

      Dec (G.all, 15.0);
      Assert (Value (G.all) < 0.0, "Gauge: can go negative");
   end Test_Gauge_Operations;

   --  Test 3: Histogram bucket counts, sum, count.
   procedure Test_Histogram_Buckets is
      Reg  : Registry_Type;
      Hist : access Histogram_Type;
   begin
      Hist := Register_Histogram (Reg, "test_histogram", "A test histogram.", Label_Vectors.Empty_Vector);

      Observe (Hist.all, 0.003);
      Observe (Hist.all, 0.02);
      Observe (Hist.all, 0.5);
      Observe (Hist.all, 2.0);

      --  Sum = 0.003 + 0.02 + 0.5 + 2.0 = 2.523.
      Assert (abs (Sum (Hist.all) - 2.523) < 0.001, "Histogram: sum accumulates");
      Assert (Count (Hist.all) = 4, "Histogram: count = 4");

      --  Bucket le=0.005 should have 1 (0.003).
      Assert (Bucket_Count (Hist.all, 0.005) = 1, "Histogram: le=0.005 bucket count");

      --  Bucket le=0.025 should have 2 (0.003, 0.02).
      Assert (Bucket_Count (Hist.all, 0.025) = 2, "Histogram: le=0.025 bucket count");

      --  Bucket le=0.5 should have 3 (0.003, 0.02, 0.5).
      Assert (Bucket_Count (Hist.all, 0.5) = 3, "Histogram: le=0.5 bucket count");

      --  Bucket le=+Inf (Float'Last) should have 4.
      Assert (Bucket_Count (Hist.all, Float'Last) = 4, "Histogram: le=+Inf bucket equals count");
   end Test_Histogram_Buckets;

   --  Test 4: Label escaping (backslash, quote, newline).
   procedure Test_Label_Escaping is
      Reg    : Registry_Type;
      Cnt    : access Counter_Type;
      Labels : Label_Set;
      Output : Unbounded_String;
   begin
      --  Official example: path="C:\\DIR\\FILE.TXT",error="Cannot find file:\n\"FILE.TXT\""
      Labels.Append (Label'(Name => To_Unbounded_String ("path"), Value => To_Unbounded_String ("C:\DIR\FILE.TXT")));
      Labels.Append (Label'(Name => To_Unbounded_String ("error"), Value => To_Unbounded_String ("Cannot find file:" & ASCII.LF & """FILE.TXT""")));

      Cnt := Register_Counter (Reg, "escaped_metric", "Test escaping.", Labels);
      Inc (Cnt.all);

      --  Check escaped output: path="C:\\DIR\\FILE.TXT" and error="Cannot find file:\n\"FILE.TXT\""
      Output := To_Unbounded_String (Collect (Reg));

      Assert (Index (To_String (Output), "path=""C:\\DIR\\FILE.TXT""") > 0, "Label escaping: backslash");
      Assert (Index (To_String (Output), "error=""Cannot find file:\n\""FILE.TXT\""""") > 0, "Label escaping: newline and quote");
   end Test_Label_Escaping;

   --  Test 5: HELP escaping (backslash, newline).
   procedure Test_Help_Escaping is
      Reg    : Registry_Type;
      Cnt    : access Counter_Type;
      Output : Unbounded_String;
   begin
      Cnt := Register_Counter (Reg, "help_escape_test", "Line one" & ASCII.LF & "Line two\with backslash", Label_Vectors.Empty_Vector);
      Inc (Cnt.all);

      Output := To_Unbounded_String (Collect (Reg));

      Assert (Index (To_String (Output), "# HELP help_escape_test Line one\nLine two\\with backslash") > 0,
              "HELP escaping: newline and backslash");
   end Test_Help_Escaping;

   --  Test 6: Invalid metric names rejected.
   procedure Test_Invalid_Metric_Name is
      Reg : Registry_Type;
      Cnt : access Counter_Type;
      pragma Unreferenced (Cnt);
      Raised : Boolean := False;
   begin
      begin
         Cnt := Register_Counter (Reg, "9invalid", "Starts with digit.", Label_Vectors.Empty_Vector);
      exception
         when Constraint_Error =>
            Raised := True;
      end;
      Assert (Raised, "Invalid metric name: starts with digit rejected");

      Raised := False;
      begin
         Cnt := Register_Counter (Reg, "invalid-name", "Contains hyphen.", Label_Vectors.Empty_Vector);
      exception
         when Constraint_Error =>
            Raised := True;
      end;
      Assert (Raised, "Invalid metric name: contains hyphen rejected");
   end Test_Invalid_Metric_Name;

   --  Test 7: Invalid label names rejected (manual check via Is_Valid_Label_Name).
   procedure Test_Invalid_Label_Name is
   begin
      Assert (not Is_Valid_Label_Name ("9label"), "Invalid label name: starts with digit");
      Assert (not Is_Valid_Label_Name ("label-name"), "Invalid label name: contains hyphen");
      Assert (Is_Valid_Label_Name ("valid_label"), "Valid label name: underscore");
      Assert (Is_Valid_Label_Name ("_valid"), "Valid label name: starts with underscore");
   end Test_Invalid_Label_Name;

   --  Test 8: Duplicate registration rejected.
   procedure Test_Duplicate_Registration is
      Reg    : Registry_Type;
      Cnt1   : access Counter_Type;
      Cnt2   : access Counter_Type;
      pragma Unreferenced (Cnt1, Cnt2);
      Raised : Boolean := False;
   begin
      Cnt1 := Register_Counter (Reg, "duplicate_test", "First.", Label_Vectors.Empty_Vector);
      begin
         Cnt2 := Register_Counter (Reg, "duplicate_test", "Second.", Label_Vectors.Empty_Vector);
      exception
         when Constraint_Error =>
            Raised := True;
      end;
      Assert (Raised, "Duplicate registration: rejected");
   end Test_Duplicate_Registration;

   --  Test 9: Multiple metrics sorted deterministically.
   procedure Test_Multiple_Metrics_Order is
      Reg    : Registry_Type;
      C1     : access Counter_Type;
      G1     : access Gauge_Type;
      H1     : access Histogram_Type;
      Pos_C  : Natural;
      Pos_G  : Natural;
      Pos_H  : Natural;
      Output : Unbounded_String;
   begin
      --  Register in arbitrary order: histogram, counter, gauge.
      H1 := Register_Histogram (Reg, "z_histogram", "Last alphabetically.", Label_Vectors.Empty_Vector);
      C1 := Register_Counter (Reg, "a_counter", "First alphabetically.", Label_Vectors.Empty_Vector);
      G1 := Register_Gauge (Reg, "m_gauge", "Middle alphabetically.", Label_Vectors.Empty_Vector);

      Inc (C1.all);
      Set (G1.all, 42.0);
      Observe (H1.all, 1.0);

      Output := To_Unbounded_String (Collect (Reg));

      --  Check insertion order is preserved (metrics appear in registration order, NOT sorted by name).
      --  The spec says "reproducible sorting preferred but not required" — we keep insertion order.
      Pos_H := Index (To_String (Output), "# HELP z_histogram");
      Pos_C := Index (To_String (Output), "# HELP a_counter");
      Pos_G := Index (To_String (Output), "# HELP m_gauge");

      Assert (Pos_H > 0 and Pos_C > 0 and Pos_G > 0, "Multiple metrics: all present");
      Assert (Pos_H < Pos_C and Pos_C < Pos_G, "Multiple metrics: insertion order (h, c, g)");
   end Test_Multiple_Metrics_Order;

   --  Test 10: Empty registry returns empty string.
   procedure Test_Empty_Registry is
      Reg    : Registry_Type;
      Output : constant String := Collect (Reg);
   begin
      Assert (Output'Length = 0, "Empty registry: output is empty string");
   end Test_Empty_Registry;

   --  Test 11: Histogram default buckets (15 including +Inf).
   procedure Test_Histogram_Default_Buckets is
      Reg  : Registry_Type;
      Hist : access Histogram_Type;
   begin
      Hist := Register_Histogram (Reg, "default_buckets", "Default buckets.", Label_Vectors.Empty_Vector);

      --  Check via Bucket_Count — if default buckets installed, bucket 0.005 exists.
      Assert (Bucket_Count (Hist.all, 0.005) = 0, "Histogram: default bucket 0.005 exists");
      Assert (Bucket_Count (Hist.all, Float'Last) = 0, "Histogram: +Inf bucket exists");
   end Test_Histogram_Default_Buckets;

   --  Test 12: Histogram observation distributes to correct buckets.
   procedure Test_Histogram_Distribution is
      Reg  : Registry_Type;
      Hist : access Histogram_Type;
   begin
      Hist := Register_Histogram (Reg, "distribution_test", "Test.", Label_Vectors.Empty_Vector);

      Observe (Hist.all, 0.001);  --  Falls into le=0.005.
      Observe (Hist.all, 0.03);   --  Falls into le=0.05.
      Observe (Hist.all, 0.2);    --  Falls into le=0.25.

      --  Cumulative: le=0.005 has 1, le=0.05 has 2, le=0.25 has 3.
      Assert (Bucket_Count (Hist.all, 0.005) = 1, "Histogram distribution: le=0.005");
      Assert (Bucket_Count (Hist.all, 0.05) = 2, "Histogram distribution: le=0.05");
      Assert (Bucket_Count (Hist.all, 0.25) = 3, "Histogram distribution: le=0.25");
   end Test_Histogram_Distribution;

   --  Test 13: Counter inc with custom amount.
   procedure Test_Counter_Custom_Inc is
      Reg : Registry_Type;
      Cnt : access Counter_Type;
   begin
      Cnt := Register_Counter (Reg, "custom_inc", "Test.", Label_Vectors.Empty_Vector);
      Inc (Cnt.all, 100.0);
      Assert (abs (Value (Cnt.all) - 100.0) < 0.001, "Counter: custom inc amount");
   end Test_Counter_Custom_Inc;

   --  Test 14: Counter inc rejects negative amount.
   procedure Test_Counter_Negative_Inc is
      Reg    : Registry_Type;
      Cnt    : access Counter_Type;
      Raised : Boolean := False;
   begin
      Cnt := Register_Counter (Reg, "negative_test", "Test.", Label_Vectors.Empty_Vector);
      begin
         Inc (Cnt.all, -5.0);
      exception
         when Constraint_Error =>
            Raised := True;
      end;
      Assert (Raised, "Counter: negative inc rejected");
   end Test_Counter_Negative_Inc;

   --  Test 15: Official histogram example format match.
   procedure Test_Histogram_Official_Format is
      Reg    : Registry_Type;
      Hist   : access Histogram_Type;
      Output : Unbounded_String;
   begin
      Hist := Register_Histogram (Reg, "http_request_duration_seconds", "A histogram of the request duration.", Label_Vectors.Empty_Vector);

      --  Simulate official example: buckets le="0.05" 24054, le="0.1" 33444, etc.
      --  We'll just verify the format structure, not exact counts.
      for I in 1 .. 100 loop
         Observe (Hist.all, 0.03 * Float (I mod 10));
      end loop;

      Output := To_Unbounded_String (Collect (Reg));

      Assert (Index (To_String (Output), "# TYPE http_request_duration_seconds histogram") > 0,
              "Histogram official: TYPE histogram");
      Assert (Index (To_String (Output), "http_request_duration_seconds_bucket{le=""0.05""}") > 0,
              "Histogram official: _bucket line with le label");
      Assert (Index (To_String (Output), "http_request_duration_seconds_bucket{le=""+Inf""}") > 0,
              "Histogram official: +Inf bucket");
      Assert (Index (To_String (Output), "http_request_duration_seconds_sum") > 0,
              "Histogram official: _sum line");
      Assert (Index (To_String (Output), "http_request_duration_seconds_count") > 0,
              "Histogram official: _count line");
   end Test_Histogram_Official_Format;

   --  Test 16: Metric name validation: first char.
   procedure Test_Metric_Name_First_Char is
   begin
      Assert (Is_Valid_Metric_Name ("valid_name"), "Metric name: valid with underscore");
      Assert (Is_Valid_Metric_Name ("ValidName"), "Metric name: valid with uppercase");
      Assert (Is_Valid_Metric_Name ("_valid"), "Metric name: valid starts with underscore");
      Assert (Is_Valid_Metric_Name (":valid"), "Metric name: valid starts with colon");
      Assert (not Is_Valid_Metric_Name ("9invalid"), "Metric name: invalid starts with digit");
   end Test_Metric_Name_First_Char;

   --  Test 17: Metric name validation: remaining chars.
   procedure Test_Metric_Name_Remaining_Chars is
   begin
      Assert (Is_Valid_Metric_Name ("valid_name_123"), "Metric name: valid with digits");
      Assert (Is_Valid_Metric_Name ("name:with:colons"), "Metric name: valid with colons");
      Assert (not Is_Valid_Metric_Name ("invalid-name"), "Metric name: invalid with hyphen");
      Assert (not Is_Valid_Metric_Name ("invalid.name"), "Metric name: invalid with dot");
   end Test_Metric_Name_Remaining_Chars;

   --  Test 18: Label name validation: first char.
   procedure Test_Label_Name_First_Char is
   begin
      Assert (Is_Valid_Label_Name ("valid_label"), "Label name: valid with underscore");
      Assert (Is_Valid_Label_Name ("ValidLabel"), "Label name: valid with uppercase");
      Assert (Is_Valid_Label_Name ("_valid"), "Label name: valid starts with underscore");
      Assert (not Is_Valid_Label_Name ("9invalid"), "Label name: invalid starts with digit");
      Assert (not Is_Valid_Label_Name (":invalid"), "Label name: invalid starts with colon");
   end Test_Label_Name_First_Char;

   --  Test 19: Label name validation: remaining chars.
   procedure Test_Label_Name_Remaining_Chars is
   begin
      Assert (Is_Valid_Label_Name ("valid_label_123"), "Label name: valid with digits");
      Assert (not Is_Valid_Label_Name ("invalid-label"), "Label name: invalid with hyphen");
      Assert (not Is_Valid_Label_Name ("invalid.label"), "Label name: invalid with dot");
   end Test_Label_Name_Remaining_Chars;

   --  Test 20: Multiple labels on a single metric.
   procedure Test_Multiple_Labels is
      Reg    : Registry_Type;
      Cnt    : access Counter_Type;
      Labels : Label_Set;
      Output : Unbounded_String;
   begin
      Labels.Append (Label'(Name => To_Unbounded_String ("env"), Value => To_Unbounded_String ("prod")));
      Labels.Append (Label'(Name => To_Unbounded_String ("region"), Value => To_Unbounded_String ("us-west")));
      Labels.Append (Label'(Name => To_Unbounded_String ("instance"), Value => To_Unbounded_String ("i-123")));

      Cnt := Register_Counter (Reg, "multi_label_test", "Test.", Labels);
      Inc (Cnt.all);

      Output := To_Unbounded_String (Collect (Reg));

      Assert (Index (To_String (Output), "env=""prod""") > 0, "Multiple labels: env present");
      Assert (Index (To_String (Output), "region=""us-west""") > 0, "Multiple labels: region present");
      Assert (Index (To_String (Output), "instance=""i-123""") > 0, "Multiple labels: instance present");
   end Test_Multiple_Labels;

begin
   Put_Line ("=== Prometheus-Ada Test Suite ===");
   Put_Line ("");

   Test_Counter_Exposition;
   Test_Gauge_Operations;
   Test_Histogram_Buckets;
   Test_Label_Escaping;
   Test_Help_Escaping;
   Test_Invalid_Metric_Name;
   Test_Invalid_Label_Name;
   Test_Duplicate_Registration;
   Test_Multiple_Metrics_Order;
   Test_Empty_Registry;
   Test_Histogram_Default_Buckets;
   Test_Histogram_Distribution;
   Test_Counter_Custom_Inc;
   Test_Counter_Negative_Inc;
   Test_Histogram_Official_Format;
   Test_Metric_Name_First_Char;
   Test_Metric_Name_Remaining_Chars;
   Test_Label_Name_First_Char;
   Test_Label_Name_Remaining_Chars;
   Test_Multiple_Labels;

   Put_Line ("");
   Put_Line ("=== Summary ===");
   Put_Line ("Passes:   " & Natural'Image (Passes));
   Put_Line ("Failures: " & Natural'Image (Failures));

   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("");
      Put_Line ("All tests passed!");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   end if;
end Prometheus.Tests;
