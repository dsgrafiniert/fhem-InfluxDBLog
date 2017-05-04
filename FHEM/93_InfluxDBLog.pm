##############################################
# $Id$
package main;

use strict;
use warnings;
use InfluxDB::HTTP;

#####################################
sub
InfluxDBLog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "InfluxDBLog_Define";
  $hash->{NotifyFn} = "InfluxDBLog_Log";
  $hash->{AttrFn}   = "InfluxDBLog_Attr";

  no warnings 'qw';
  my @attrList = qw(
    addStateEvent:1,0
    disable:1,0
    disabledForIntervals
    numberFormat
    readySuffix
    syncAfterWrite:1,0
    template:textField-long
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);
}


#####################################
sub
InfluxDBLog_Define($@)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $fh;

  return "wrong syntax: define <name> InfluxDBLog InfluxDBServer InfluxDBPort regexp"
        if(int(@a) != 5);

  return "Bad regexp: starting with *" if($a[3] =~ m/^\*/);
  eval { "Hallo" =~ m/^$a[3]$/ };
  return "Bad regexp: $@" if($@);

  $hash->{FH} = $fh;
  $hash->{REGEXP} = $a[4];
  $hash->{INFLUXSRV} = $a[2];
  $hash->{INFLUXPORT} = int($a[3]);
  $hash->{STATE} = "active";
  readingsSingleUpdate($hash, "filecount", 0, 0);
  notifyRegexpChanged($hash, $a[4]);

  return undef;
}


#####################################
sub
InfluxDBLog_Log($$)
{
  # Log is my entry, Dev is the entry of the changed device
  my ($log, $dev) = @_;
  return if($log->{READONLY});

  my $ln = $log->{NAME};
  return if(IsDisabled($ln));
  my $events = deviceEvents($dev, AttrVal($ln, "addStateEvent", 0));
  return if(!$events);

  my $n = $dev->{NAME};
  my $re = $log->{REGEXP};
  my $max = int(@{$events});
  my $tn = $dev->{NTFY_TRIGGERTIME};
  my $ct = $dev->{CHANGETIME};

  for (my $i = 0; $i < $max; $i++) {
    my $s = $events->[$i];
    $s = "" if(!defined($s));
    my $t = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/ || "$t:$n:$s" =~ m/^$re$/) {
      my $fc = ReadingsVal($ln,"filecount",0)+1;
      readingsSingleUpdate($log, "filecount", $fc, 0);

      my %arg = (log=>$log, dev=>$dev, evt=>$s);
      
        InfluxDBLog_Write(\%arg);
      
    }
  }
  return "";
}

###################################
sub
InfluxDBLog_Write($)
{
  my ($ptr) = @_;
  my ($log, $dev, $EVENT) = ($ptr->{log}, $ptr->{dev}, $ptr->{evt});
  my $NAME = $dev->{NAME};

  my $ln = $log->{NAME};
  my ($seconds, $microseconds) = gettimeofday();

  my @time = localtime($seconds);
  my $f = $log->{LOGFILE};
  my $fc = ReadingsVal($ln,"filecount",0);
  $f =~ s/%Q/$fc/g;
  $f = ResolveDateWildcards($f, @time);
  Log3 $ln, 4, "$ln: Writing $f";

  my $time = $dev->{NTFY_TRIGGERTIME};
  my $time14 = sprintf("%04d%02d%02d%02d%02d%02d",
                  $time[5]+1900,$time[4]+1,$time[3],$time[2],$time[1],$time[0]);
  my $time16 = $time14.sprintf("%02d", $microseconds/100000);
  my ($decl,$idx) = ("",0);
  my $nf = AttrVal($ln, "numberFormat", "%1.6E");
  foreach my $part (split(" ", $EVENT)) {
    $decl .= "my \$EVTPART$idx='$part';";
    $decl .= "my \$EVTNUM$idx='".sprintf($nf,$part)."';"
        if(looks_like_number($part));
    $idx++;
  }

  my $template = AttrVal($ln, "template", '$time $NAME $EVENT\n');
  $template = "\"$template\"" if($template !~ m/^{.*}$/);

  my $data = eval "$decl $template";
  if($@) {
    Log3 $ln, 1, "$ln: error evaluating template: $@";
    return;
  }
  $data =~ s/\n/\r\n/mg if(AttrVal($ln, "dosLineEnding", 0));

  my $fh = new IO::File ">>$f.tmp";
  if(!defined($fh)) {
    Log3 $ln, 1, "$ln: Can't open $f.tmp: $!";
    return;
  }
  print $fh $data;
  $fh->sync if($^O ne 'MSWin32' && AttrVal($ln, "syncAfterWrite", 0));
  close($fh);


}

###################################
sub
InfluxDBLog_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");

  return undef;
}

1;

=pod
=item helper
=item summary    write single events to a separate file each, using templates
=item summary_DE schreibt einzelne Events in separate Dateien via templates
=begin html

<a name="InfluxDBLog"></a>
<h3>InfluxDBLog</h3>
<ul>
  <br>

  <a name="InfluxDBLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; InfluxDBLog &lt;filename&gt; &lt;regexp&gt;
    </code>
    <br><br>
    For each event or devicename:event matching the &lt;regexp&gt; create a
    new file &lt;filename&gt;<br>
    <code>&lt;filename&gt;</code> may contain %-wildcards of the
    POSIX strftime function of the underlying OS (see your strftime manual),
    additionally %Q is replaced with a sequential number unique to the
    InfluxDBLog device. The file content is based on the template attribute,
    see below.<br>
    If the filename is enclosed in {} then it is evaluated as a perl expression,
    which can be used to use a global path different from %L.
  </ul>
  <br>

  <a name="InfluxDBLogset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="InfluxDBLogget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="InfluxDBLogattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#addStateEvent">addStateEvent</a></li><br>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li><br>


    <li><a name="#numberFormat">numberFormat</a><br>
      If a word in the event looks like a number, then it is reformatted using
      the numberFormat, and $EVTNUMx is set (analogue to $EVTPARx). Default is
      %1.6E, see the printf manual for details.
    </li><br>

    <li><a name="#template">template</a><br>
      This attribute specifies the content of the file. Following variables
      are replaced before writing the file:
      <ul>
        <li>$EVENT - the complete event</li>
        <li>$EVTPART0 $EVTPART1 ... - the event broken into single words</li>
        <li>$EVTNUM0 $EVTNUM1 ... - reformatted as numbers, see numberFormat
            above</li>
        <li>$NAME - the name of the device generating the event</li>
        <li>$time - the current time, formatted as YYYY-MM-DD HH:MM:SS</li>
        <li>$time14 - the current time, formatted as YYYYMMDDHHMMSS</li>
        <li>$time16 - the current time, formatted as YYYYMMDDHHMMSSCC,
            where CC is the hundredth second</li>
      </ul>
      If the template is enclosed in {} than it will be evaluated as a perl
      expression, and its result is written to the file.<br>
      Default is $time $NAME $EVENT\n
    </li><br>
  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="InfluxDBLog"></a>
<h3>InfluxDBLog</h3>
<ul>
  <br>

  <a name="InfluxDBLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; InfluxDBLog &lt;filename&gt; &lt;regexp&gt;
    </code>
    <br><br>
    F&uuml; jedes Event oder Ger&auml;tename:Event, worauf &lt;regexp&gt;
    zutrifft, wird eine separate Datei angelegt, der Inhalt wird von dem
    template Attribut gesteuert (s.u.).
    <code>&lt;filename&gt;</code> kann %-Wildcards der POSIX strftime-Funktion
    des darunterliegenden OS enthalten (siehe auch man strftime).
    Zus&auml;tzlich wird %Q durch eine fortlaufende Zahl ersetzt.<br>
    Falls filename in {} eingeschlossen ist, dann wird sie als perl-Ausdruck
    ausgewertet, was erm&ouml;glicht einen vom %L abweichenden globalem Pfad zu
    definieren.
  </ul>
  <br>

  <a name="InfluxDBLogset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="InfluxDBLogget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="InfluxDBLogattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#addStateEvent">addStateEvent</a></li><br>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li><br>


    <li><a name="#numberFormat">numberFormat</a><br>
      Falls ein Wort im Event wie eine Zahl aussieht, dann wird es wie in
      numberFormat angegeben, umformatiert, und als $EVTNUMx (analog zu
      $EVTPARTx) zur Verf&uuml;gung gestellt. Voreinstellung ist %1.6E, siehe
      die printf Formatbeschreibung f&uuml;r Details.
    </li><br>

    <li><a name="#template">template</a><br>
      Damit wird der Inhalt der geschriebenen Datei spezifiziert. Folgende
      Variablen werden vor dem Schreiben der Datei ersetzt:
      <ul>
        <li>$EVENT - das vollst&auml;ndige Event.</li>
        <li>$EVTPART0 $EVTPART1 ... - die einzelnen W&ouml;rter des Events.</li>
        <li>$EVTNUM0 $EVTNUM1 ... - umformatiert als Zahl, siehe numberFormat
            weiter oben.</li>
        <li>$NAME - der Name des Ger&auml;tes, das das Event generiert.</li>
        <li>$time - die aktuelle Zeit, formatiert als YYYY-MM-DD HH:MM:SS</li>
        <li>$time14 - die aktuelle Zeit, formatiert als YYYYMMDDHHMMSS</li>
        <li>$time16 - die aktuelle Zeit, formatiert als YYYYMMDDHHMMSSCC,
            wobei CC die hundertstel Sekunde ist</li>
      </ul>
      Falls template in {} eingeschlossen ist, dann wird er als perl-Ausdruck
      ausgefuehrt, und das Ergebnis wird in die Datei geschrieben.<br>
      Die Voreinstellung ist $time $NAME $EVENT\n
    </li><br>
  </ul>
  <br>
</ul>

=end html_DE

=cut