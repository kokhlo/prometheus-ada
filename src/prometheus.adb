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
      if Amount < 0.0 then
         raise Constraint_Error with "Counter increment must be non-negative";
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
            if Val <= B.Upper_Bound then
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

   function Register_Counter
     (Self   : in out Registry_Type;
      Name   : String;
      Help   : String;
      Labels : Label_Set := Label_Vectors.Empty_Vector)
      return Counter_Access
   is
      UName : constant Unbounded_String := To_Unbounded_String (Name);
      Cnt   : Counter_Access;
   begin
      if not Is_Valid_Metric_Name (Name) then
         raise Constraint_Error with "Invalid metric name: " & Name;
      end if;

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
                            Labels    => Labels,
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
      G     : Gauge_Access;
   begin
      if not Is_Valid_Metric_Name (Name) then
         raise Constraint_Error with "Invalid metric name: " & Name;
      end if;

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
                            Labels    => Labels,
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
      H           : Histogram_Access;
      Bucket_List : Bucket_Vectors.Vector;
   begin
      if not Is_Valid_Metric_Name (Name) then
         raise Constraint_Error with "Invalid metric name: " & Name;
      end if;

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
               if UB_Str = "+Inf" then
                  UB := Float'Last;
               else
                  UB := Float'Value (UB_Str);
               end if;
               Bucket_List.Append (Bucket'(Upper_Bound => UB, Count => 0));
            end;
         end loop;
      end if;

      H := new Histogram_Type;
      H.Buckets_Vec := Bucket_List;

      Self.Metrics.Append
        (Metric_Descriptor'(Kind      => Kind_Histogram,
                            Name      => UName,
                            Help      => To_Unbounded_String (Help),
                            Labels    => Labels,
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
         S : constant String := Float'Image (Val);
         T : constant String := (if S'Length > 0 and then S (S'First) = ' '
                                 then S (S'First + 1 .. S'Last)
                                 else S);
         E : constant Integer := Index (T, "E");
      begin
         --  Exponent form (e.g. 5.00000E-02) is valid for scrapers but ugly and
         --  unlike every other client; render plain decimal where possible.
         if E = 0 then
            return T;
         end if;
         declare
            Mantissa : constant String := T (T'First .. E - 1);
            Exp      : constant Integer := Integer'Value (T (E + 1 .. T'Last));
            Dg       : constant String := Mantissa (Mantissa'First .. Index (Mantissa, ".") - 1)
                                       & Mantissa (Index (Mantissa, ".") + 1 .. Mantissa'Last);
            Point    : constant Integer := Index (Mantissa, ".") - Mantissa'First; -- digits before point
         begin
            if Exp < 0 and then -Exp < Point then
               --  Shift the point left: 0.05 style
               return Trim_Zeros ("0." & (-Exp - Point - 1) * '0' & Dg);
            elsif Exp < 0 then
               return Trim_Zeros ("0." & ((-Exp) - 1) * '0' & Dg);
            else
               if Point + Exp >= Dg'Length then
                  return Trim_Zeros (Dg & (Point + Exp - Dg'Length) * '0');
               else
                  return Trim_Zeros (Dg (Dg'First .. Dg'First + Point + Exp - 1) & "."
                    & Dg (Dg'First + Point + Exp .. Dg'Last));
               end if;
            end if;
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

   function Is_Valid_Metric_Name (Name : String) return Boolean is
   begin
      if Name'Length = 0 then
         return False;
      end if;

      --  First char: [a-zA-Z_:]
      if not (Is_Letter (Name (Name'First)) or else Name (Name'First) in '_' | ':') then
         return False;
      end if;

      --  Remaining: [a-zA-Z0-9_:]
      for I in Name'First + 1 .. Name'Last loop
         if not (Is_Alphanumeric (Name (I)) or else Name (I) in '_' | ':') then
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
      if not (Is_Letter (Name (Name'First)) or else Name (Name'First) = '_') then
         return False;
      end if;

      --  Remaining: [a-zA-Z0-9_]
      for I in Name'First + 1 .. Name'Last loop
         if not (Is_Alphanumeric (Name (I)) or else Name (I) = '_') then
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
