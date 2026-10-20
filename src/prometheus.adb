--  Prometheus text-format metrics client implementation.

with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed;       use Ada.Strings.Fixed;

package body Prometheus is

   --  Default histogram buckets (Go client compatible).
   Default_Buckets : constant array (1 .. 15) of Float :=
     (0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0,
      2.5, 5.0, 7.5, 10.0, Float'Last);

   -----------------
   -- Counter_Type
   -----------------

   procedure Inc (Self : in out Counter_Type; Amount : Float := 1.0) is
   begin
      --  NaN must be rejected explicitly: every comparison with NaN is
      --  False, so "Amount < 0.0" alone would let it through and poison
      --  the counter forever (counters must stay monotonic).
      if Amount < 0.0 or else Amount /= Amount then
         raise Constraint_Error with "Counter increment must be a non-negative number";
      end if;
      Self.Val := Self.Val + Amount;
   end Inc;

   function Value (Self : Counter_Type) return Float is
   begin
      return Self.Val;
   end Value;

   ---------------
   -- Gauge_Type
   ---------------

   procedure Inc (Self : in out Gauge_Type; Amount : Float := 1.0) is
   begin
      Self.Val := Self.Val + Amount;
   end Inc;

   procedure Dec (Self : in out Gauge_Type; Amount : Float := 1.0) is
   begin
      Self.Val := Self.Val - Amount;
   end Dec;

   procedure Set (Self : in out Gauge_Type; Val : Float) is
   begin
      Self.Val := Val;
   end Set;

   function Value (Self : Gauge_Type) return Float is
   begin
      return Self.Val;
   end Value;

   -------------------
   -- Histogram_Type
   -------------------

   procedure Observe (Self : in out Histogram_Type; Val : Float) is
   begin
      Self.Sum_Val := Self.Sum_Val + Val;
      Self.Count_Val := Self.Count_Val + 1;

      for I in Self.Buckets_Vec.First_Index .. Self.Buckets_Vec.Last_Index loop
         declare
            B : Bucket := Self.Buckets_Vec.Element (I);
         begin
            --  A bucket with Upper_Bound = Float'Last is the le="+Inf"
            --  bucket; it is inclusive of an actual +Inf observation
            --  (Val > Float'Last), which every "Val <= bound" test would
            --  otherwise miss.
            if Val <= B.Upper_Bound
              or else (B.Upper_Bound = Float'Last and then Val > Float'Last)
            then
               B.Count := B.Count + 1;
               Self.Buckets_Vec.Replace_Element (I, B);
            end if;
         end;
      end loop;
   end Observe;

   function Bucket_Count (Self : Histogram_Type; Upper_Bound : Float) return Natural is
   begin
      for B of Self.Buckets_Vec loop
         if B.Upper_Bound = Upper_Bound then
            return B.Count;
         end if;
      end loop;
      return 0;
   end Bucket_Count;

   function Sum (Self : Histogram_Type) return Float is
   begin
      return Self.Sum_Val;
   end Sum;

   function Count (Self : Histogram_Type) return Natural is
   begin
      return Self.Count_Val;
   end Count;

   -------------------
   -- Registry_Type
   -------------------

   --  Validate every label name and sort the set by name.  The text
   --  format spec requires deterministic label order within a metric;
   --  sorted-by-name also makes duplicate label names adjacent so the
   --  uniqueness check can catch them.
   procedure Prepare_Labels (Labels : in out Label_Set) is

      function Less (X, Y : Label) return Boolean is
        (To_String (X.Name) < To_String (Y.Name));

      package Label_Sorting is new Label_Vectors.Generic_Sorting (Less);

   begin
      for L of Labels loop
         if not Is_Valid_Label_Name (To_String (L.Name)) then
            raise Constraint_Error
              with "Invalid label name: " & To_String (L.Name);
         end if;
      end loop;

      for I in Labels.First_Index .. Labels.Last_Index - 1 loop
         for J in I + 1 .. Labels.Last_Index loop
            if To_String (Labels.Element (I).Name)
              = To_String (Labels.Element (J).Name)
            then
               raise Constraint_Error
                 with "Duplicate label name: " & To_String (Labels.Element (I).Name);
            end if;
         end loop;
      end loop;

      Label_Sorting.Sort (Labels);
   end Prepare_Labels;

   --  Sort buckets by upper bound, ascending.  The text format requires
   --  le values to appear in increasing order; the +Inf bucket
   --  (Float'Last) naturally sorts last.  A user-supplied +Inf is mapped
   --  to Float'Last so it shares the sentinel.
   procedure Sort_Buckets (Buckets : in out Bucket_Vectors.Vector) is

      function Less (X, Y : Bucket) return Boolean is
        (X.Upper_Bound < Y.Upper_Bound);

      package Bucket_Sorting is new Bucket_Vectors.Generic_Sorting (Less);

   begin
      Bucket_Sorting.Sort (Buckets);
   end Sort_Buckets;

   function Register_Counter
     (Self   : in out Registry_Type;
      Name   : String;
      Help   : String;
      Labels : Label_Set := Label_Vectors.Empty_Vector)
      return Counter_Access
   is
      UName  : constant Unbounded_String := To_Unbounded_String (Name);
      Lbls   : Label_Set := Labels;
      Cnt    : Counter_Access;
   begin
      if not Is_Valid_Metric_Name (Name) then
         raise Constraint_Error with "Invalid metric name: " & Name;
      end if;

      Prepare_Labels (Lbls);

      --  Check for duplicate.
      for M of Self.Metrics loop
         if M.Name = UName then
            raise Constraint_Error with "Duplicate metric name: " & Name;
         end if;
      end loop;

      Cnt := new Counter_Type;
      Self.Metrics.Append
        (Metric_Descriptor'(Kind      => Kind_Counter,
                            Name      => UName,
                            Help      => To_Unbounded_String (Help),
                            Labels    => Lbls,
                            Counter   => Cnt,
                            Gauge     => null,
                            Histogram => null));

      return Cnt;
   end Register_Counter;

   function Register_Gauge
     (Self   : in out Registry_Type;
      Name   : String;
      Help   : String;
      Labels : Label_Set := Label_Vectors.Empty_Vector)
      return Gauge_Access
   is
      UName : constant Unbounded_String := To_Unbounded_String (Name);
      Lbls  : Label_Set := Labels;
      G     : Gauge_Access;
   begin
      if not Is_Valid_Metric_Name (Name) then
         raise Constraint_Error with "Invalid metric name: " & Name;
      end if;

      Prepare_Labels (Lbls);

      for M of Self.Metrics loop
         if M.Name = UName then
            raise Constraint_Error with "Duplicate metric name: " & Name;
         end if;
      end loop;

      G := new Gauge_Type;
      Self.Metrics.Append
        (Metric_Descriptor'(Kind      => Kind_Gauge,
                            Name      => UName,
                            Help      => To_Unbounded_String (Help),
                            Labels    => Lbls,
                            Counter   => null,
                            Gauge     => G,
                            Histogram => null));

      return G;
   end Register_Gauge;

   function Register_Histogram
     (Self    : in out Registry_Type;
      Name    : String;
      Help    : String;
      Labels  : Label_Set := Label_Vectors.Empty_Vector;
      Buckets : Label_Vectors.Vector := Label_Vectors.Empty_Vector)
      return Histogram_Access
   is
      UName       : constant Unbounded_String := To_Unbounded_String (Name);
      Lbls        : Label_Set := Labels;
      H           : Histogram_Access;
      Bucket_List : Bucket_Vectors.Vector;
   begin
      if not Is_Valid_Metric_Name (Name) then
         raise Constraint_Error with "Invalid metric name: " & Name;
      end if;

      Prepare_Labels (Lbls);

      for M of Self.Metrics loop
         if M.Name = UName then
            raise Constraint_Error with "Duplicate metric name: " & Name;
         end if;
      end loop;

      --  Use default buckets if empty.
      if Buckets.Is_Empty then
         for UB of Default_Buckets loop
            Bucket_List.Append (Bucket'(Upper_Bound => UB, Count => 0));
         end loop;
      else
         --  User-provided buckets (assume sorted).
         for L of Buckets loop
            declare
               UB_Str : constant String := To_String (L.Value);
               UB     : Float;
            begin
               if UB_Str = "+Inf" or else UB_Str = "Inf" or else UB_Str = "-Inf" then
                  if UB_Str = "-Inf" then
                     raise Constraint_Error
                       with "Invalid bucket bound: " & UB_Str;
                  end if;
                  UB := Float'Last;
               else
                  UB := Float'Value (UB_Str);
               end if;
               Bucket_List.Append (Bucket'(Upper_Bound => UB, Count => 0));
            end;
         end loop;
      end if;

      Sort_Buckets (Bucket_List);

      H := new Histogram_Type;
      H.Buckets_Vec := Bucket_List;

      Self.Metrics.Append
        (Metric_Descriptor'(Kind      => Kind_Histogram,
                            Name      => UName,
                            Help      => To_Unbounded_String (Help),
                            Labels    => Lbls,
                            Counter   => null,
                            Gauge     => null,
                            Histogram => H));

      return H;
   end Register_Histogram;

   function Collect (Self : Registry_Type) return String is
      Result : Unbounded_String;

      procedure Append_Line (Line : String) is
      begin
         Append (Result, Line & ASCII.LF);
      end Append_Line;

      function Format_Labels (Labels : Label_Set) return String is
         Buf : Unbounded_String;
      begin
         if Labels.Is_Empty then
            return "";
         end if;

         Append (Buf, "{");
         for I in Labels.First_Index .. Labels.Last_Index loop
            if I > Labels.First_Index then
               Append (Buf, ",");
            end if;
            Append (Buf, To_String (Labels (I).Name));
            Append (Buf, "=""");
            Append (Buf, Escape_Label_Value (To_String (Labels (I).Value)));
            Append (Buf, """");
         end loop;
         Append (Buf, "}");
         return To_String (Buf);
      end Format_Labels;

      --  Drop trailing zeros after the decimal point; keep at least one digit
      --  after it, and drop the point entirely for whole numbers.
      function Trim_Zeros (S : String) return String is
         Last : Integer := S'Last;
      begin
         if Index (S, ".") = 0 then
            return S;
         end if;
         while Last > S'First and then S (Last) = '0' loop
            Last := Last - 1;
         end loop;
         if Last > S'First and then S (Last) = '.' then
            Last := Last - 1;
         end if;
         return S (S'First .. Last);
      end Trim_Zeros;

      function Format_Float (Val : Float) return String is
      begin
         --  Non-finite values have dedicated tokens in the text format.
         --  Float'Image renders them as "+Inf****"-style padded strings,
         --  so they must be handled before any decimal surgery.
         if Val /= Val then
            return "NaN";
         elsif Val > Float'Last then
            return "+Inf";
         elsif Val < -Float'Last then
            return "-Inf";
         end if;

         declare
            S : constant String := Float'Image (Val);
            T : constant String := (if S (S'First) = ' '
                                    then S (S'First + 1 .. S'Last)
                                    else S);
            E : constant Integer := Index (T, "E");
         begin
            --  Exponent form (e.g. 5.00000E-02) is valid for scrapers but
            --  ugly and unlike every other client; render plain decimal.
            if E = 0 then
               return Trim_Zeros (T);
            end if;

            declare
               Neg      : constant Boolean := T (T'First) = '-';
               Mantissa : constant String :=
                 (if Neg then T (T'First + 1 .. E - 1) else T (T'First .. E - 1));
               Exp      : constant Integer := Integer'Value (T (E + 1 .. T'Last));
               Dot      : constant Integer := Index (Mantissa, ".");
               Dg       : constant String :=
                 (if Dot = 0 then Mantissa
                  else Mantissa (Mantissa'First .. Dot - 1)
                    & Mantissa (Dot + 1 .. Mantissa'Last));
               Point    : constant Integer :=
                 (if Dot = 0 then Mantissa'Length else Dot - Mantissa'First);
               NewP     : constant Integer := Point + Exp;
               --  Digits before the decimal point after applying Exp.
               Sign     : constant String := (if Neg then "-" else "");
            begin
               --  Out-of-range exponents (not producible by Float'Image,
               --  guard for other Float types) stay in valid E-notation.
               if Exp > 99 or else Exp < -99 then
                  return T;
               end if;

               if NewP <= 0 then
                  --  Shift the point left: 5.0E-2 -> 0.05
                  return Sign & Trim_Zeros ("0." & (-NewP) * '0' & Dg);
               elsif NewP >= Dg'Length then
                  --  Shift the point right past all digits: 1.0E6 -> 1000000
                  return Sign & Dg & (NewP - Dg'Length) * '0';
               else
                  --  Point lands inside the digit string: 1.5E0 -> 1.5
                  return Sign
                    & Trim_Zeros (Dg (Dg'First .. Dg'First + NewP - 1) & "."
                                    & Dg (Dg'First + NewP .. Dg'Last));
               end if;
            end;
         end;
      end Format_Float;

   begin
      if Self.Metrics.Is_Empty then
         return "";
      end if;

      --  Emit metrics in order (already ordered by insertion, or sort if needed).
      for M of Self.Metrics loop
         --  HELP line.
         Append_Line ("# HELP " & To_String (M.Name) & " " & Escape_Help_Text (To_String (M.Help)));

         --  TYPE line.
         case M.Kind is
            when Kind_Counter =>
               Append_Line ("# TYPE " & To_String (M.Name) & " counter");
               Append_Line (To_String (M.Name) & Format_Labels (M.Labels) & " " & Format_Float (M.Counter.all.Val));

            when Kind_Gauge =>
               Append_Line ("# TYPE " & To_String (M.Name) & " gauge");
               Append_Line (To_String (M.Name) & Format_Labels (M.Labels) & " " & Format_Float (M.Gauge.all.Val));

            when Kind_Histogram =>
               Append_Line ("# TYPE " & To_String (M.Name) & " histogram");

               --  Emit buckets.
               for B of M.Histogram.all.Buckets_Vec loop
                  declare
                     Le_Label : Label_Set := M.Labels;
                     Le_Str   : constant String :=
                       (if B.Upper_Bound = Float'Last then "+Inf" else Format_Float (B.Upper_Bound));
                  begin
                     Le_Label.Append (Label'(Name  => To_Unbounded_String ("le"),
                                             Value => To_Unbounded_String (Le_Str)));
                     Append_Line (To_String (M.Name) & "_bucket" & Format_Labels (Le_Label) & " " &
                                  Trim (Natural'Image (B.Count), Ada.Strings.Both));
                  end;
               end loop;

               --  Sum and count.
               Append_Line (To_String (M.Name) & "_sum" & Format_Labels (M.Labels) & " " & Format_Float (M.Histogram.all.Sum_Val));
               Append_Line (To_String (M.Name) & "_count" & Format_Labels (M.Labels) & " " &
                            Trim (Natural'Image (M.Histogram.all.Count_Val), Ada.Strings.Both));
         end case;
      end loop;

      return To_String (Result);
   end Collect;

   --  ASCII-only membership tests for name validation.  Do not replace
   --  with Ada.Characters.Handling: its Is_Letter/Is_Alphanumeric accept
   --  all of Latin-1 (e.g. 'É', 'ñ'), which the text format forbids.
   function Is_ASCII_Letter (C : Character) return Boolean is
     (C in 'A' .. 'Z' | 'a' .. 'z');

   function Is_ASCII_Digit (C : Character) return Boolean is
     (C in '0' .. '9');

   function Is_Valid_Metric_Name (Name : String) return Boolean is
   begin
      if Name'Length = 0 then
         return False;
      end if;

      --  First char: [a-zA-Z_:].  Deliberately ASCII-only membership
      --  tests (Ada.Characters.Handling.Is_Letter accepts all Latin-1
      --  letters, e.g. 'É', which are invalid in metric names).
      if not (Is_ASCII_Letter (Name (Name'First))
                or else Name (Name'First) = '_' or else Name (Name'First) = ':')
      then
         return False;
      end if;

      --  Remaining: [a-zA-Z0-9_:]
      for I in Name'First + 1 .. Name'Last loop
         if not (Is_ASCII_Letter (Name (I))
                   or else Is_ASCII_Digit (Name (I))
                   or else Name (I) = '_' or else Name (I) = ':')
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Metric_Name;

   function Is_Valid_Label_Name (Name : String) return Boolean is
   begin
      if Name'Length = 0 then
         return False;
      end if;

      --  First char: [a-zA-Z_]
      if not (Is_ASCII_Letter (Name (Name'First))
                or else Name (Name'First) = '_')
      then
         return False;
      end if;

      --  Remaining: [a-zA-Z0-9_]
      for I in Name'First + 1 .. Name'Last loop
         if not (Is_ASCII_Letter (Name (I))
                   or else Is_ASCII_Digit (Name (I))
                   or else Name (I) = '_')
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Label_Name;

   function Escape_Label_Value (Value : String) return String is
      Result : Unbounded_String;
   begin
      for C of Value loop
         case C is
            when '\' =>
               Append (Result, "\\");
            when '"' =>
               Append (Result, "\""");
            when ASCII.LF =>
               Append (Result, "\n");
            when others =>
               Append (Result, C);
         end case;
      end loop;
      return To_String (Result);
   end Escape_Label_Value;

   function Escape_Help_Text (Text : String) return String is
      Result : Unbounded_String;
   begin
      for C of Text loop
         case C is
            when '\' =>
               Append (Result, "\\");
            when ASCII.LF =>
               Append (Result, "\n");
            when others =>
               Append (Result, C);
         end case;
      end loop;
      return To_String (Result);
   end Escape_Help_Text;

end Prometheus;
