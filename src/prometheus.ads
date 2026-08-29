--  Prometheus text-format metrics client library for Ada.
--  Supports Counter, Gauge, and Histogram metric types with labels.
--  Exposition format: Prometheus text v0.0.4 (text/plain).

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Prometheus is

   --  Label is a name-value pair attached to metrics.
   --  Label names must match [a-zA-Z_][a-zA-Z0-9_]*.
   --  Label values can be any UTF-8 string (backslash, quote, newline escaped).
   type Label is record
      Name  : Unbounded_String;
      Value : Unbounded_String;
   end record;

   --  Label_Set is an ordered vector of labels (sorted by name for determinism).
   package Label_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Label);
   subtype Label_Set is Label_Vectors.Vector;

   --  Metric types supported by Prometheus.
   type Metric_Type is (Counter, Gauge, Histogram);

   --  Counter: monotonically increasing value (only Inc).
   type Counter_Type is limited private;
   procedure Inc (Self : in out Counter_Type; Amount : Float := 1.0);
   function Value (Self : Counter_Type) return Float;

   --  Gauge: arbitrary value that can go up or down.
   type Gauge_Type is limited private;
   procedure Inc (Self : in out Gauge_Type; Amount : Float := 1.0);
   procedure Dec (Self : in out Gauge_Type; Amount : Float := 1.0);
   procedure Set (Self : in out Gauge_Type; Val : Float);
   function Value (Self : Gauge_Type) return Float;

   --  Histogram: observations with cumulative buckets, sum, count.
   --  Default buckets: .005,.01,.025,.05,.075,.1,.25,.5,.75,1.0,2.5,5.0,7.5,10.0,+Inf.
   type Histogram_Type is limited private;
   procedure Observe (Self : in out Histogram_Type; Val : Float);
   function Bucket_Count (Self : Histogram_Type; Upper_Bound : Float) return Natural;
   function Sum (Self : Histogram_Type) return Float;
   function Count (Self : Histogram_Type) return Natural;

   --  Registry: holds metrics and generates text exposition.
   type Registry_Type is tagged limited private;

   type Counter_Access is access all Counter_Type;
   type Gauge_Access is access all Gauge_Type;
   type Histogram_Access is access all Histogram_Type;

   --  Register a counter with given name, help text, and labels.
   --  Raises Constraint_Error if name is invalid or duplicate.
   function Register_Counter
     (Self   : in out Registry_Type;
      Name   : String;
      Help   : String;
      Labels : Label_Set := Label_Vectors.Empty_Vector)
      return Counter_Access;

   --  Register a gauge.
   function Register_Gauge
     (Self   : in out Registry_Type;
      Name   : String;
      Help   : String;
      Labels : Label_Set := Label_Vectors.Empty_Vector)
      return Gauge_Access;

   --  Register a histogram with custom buckets (or default if empty).
   function Register_Histogram
     (Self    : in out Registry_Type;
      Name    : String;
      Help    : String;
      Labels  : Label_Set := Label_Vectors.Empty_Vector;
      Buckets : Label_Vectors.Vector := Label_Vectors.Empty_Vector)
      return Histogram_Access;

   --  Collect returns the full Prometheus text exposition (v0.0.4).
   --  Metrics sorted by name for determinism.
   function Collect (Self : Registry_Type) return String;

   --  Validation: check metric/label name format.
   function Is_Valid_Metric_Name (Name : String) return Boolean;
   function Is_Valid_Label_Name (Name : String) return Boolean;

   --  Escaping for label values: \ → \\, " → \", newline → \n.
   function Escape_Label_Value (Value : String) return String;

   --  Escaping for HELP text: \ → \\, newline → \n.
   function Escape_Help_Text (Text : String) return String;

private

   type Counter_Type is limited record
      Val : Float := 0.0;
   end record;

   type Gauge_Type is limited record
      Val : Float := 0.0;
   end record;

   --  Histogram bucket: upper_bound → cumulative count.
   type Bucket is record
      Upper_Bound : Float;
      Count       : Natural := 0;
   end record;

   package Bucket_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Bucket);

   type Histogram_Type is limited record
      Buckets_Vec : Bucket_Vectors.Vector;
      Sum_Val     : Float   := 0.0;
      Count_Val   : Natural := 0;
   end record;

   --  Metric descriptor (stored in registry).
   type Metric_Kind is (Kind_Counter, Kind_Gauge, Kind_Histogram);

   type Metric_Descriptor is record
      Kind   : Metric_Kind;
      Name   : Unbounded_String;
      Help   : Unbounded_String;
      Labels : Label_Set;
      --  Exactly one of these is non-null.
      Counter   : Counter_Access;
      Gauge     : Gauge_Access;
      Histogram : Histogram_Access;
   end record;

   package Metric_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Metric_Descriptor);

   type Registry_Type is tagged limited record
      Metrics : Metric_Vectors.Vector;
   end record;

end Prometheus;
