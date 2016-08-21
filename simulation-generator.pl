#!/usr/bin/perl
use strictures 2;
use POSIX 'ceil', 'floor';
use Imager;
use Imager::Color;
use Scalar::Util 'looks_like_number';
use Data::Printer;
use 5.12.0;
use Math::PlanePath::HilbertCurve;

my $path = Math::PlanePath::HilbertCurve->new();

# Make some texture images
my $width = 400;
my $height = 300;
my ($n_min, $n_max) = $path->rect_to_n_range(0, 0 => $width-1, $height-1);
if ($n_min != 0) {
    die "Fixme: n-range doesn't start at 0";
}
my $bits = ceil(log($n_max - $n_min) / log(2));

say "Texture size: $width x $height x $bits bits";

my $white = Imager::Color->new(255,255,255);
my $black = Imager::Color->new(0,0,0);
for my $bit (0..$bits-1) {
    my $bitval = 1<<$bit;
    say $bitval;
    make_things($bit, sub {$_ & $bitval});
    make_things($bit."-inverse", sub {!($_ & $bitval)});
}

make_things('white', sub{1});
make_things('black', sub{0});

sub make_things {
    my ($name, $function) = @_;
    
    my $filename = "$name-texture.png";
    
    if (!-e $filename) {
        print STDERR "Making texture $filename\n";
        
        my $img = Imager->new(xsize=>$width, ysize=>$height, channels=>1);
        $_ = 0;

        for my $x (0..$width-1) {
            for my $y (0..$height-1) {
                # Get rid of the very thin bits
                $_ = $path->xy_to_n($x+1, $y+1);
                $img->setpixel(x=>$x, y=>$y, color=> $function->() ? $white : $black);
            }
        }
        $img->write(file => $filename, type => 'png') or die;
    }
    
    my $lxs_filename = "$name-simulation.lxs";
    print STDERR "Outputting luxrender for $lxs_filename\n";
    my $lxs = output_lxs($name);
    open my $lxs_fh, ">", $lxs_filename or die;
    print $lxs_fh $lxs or die;
    close $lxs_fh;
    
    system("./lux-v1.6-x86_64-sse2-OpenCL/luxconsole $lxs_filename");
}


# http://www.luxrender.net/wiki/Scene_file_format_1.0#Importance_of_parameter_types
sub format_value {
  my ($value, $type, $arrayify) = @_;

  #print STDERR "format_value: ";
  #p @_;
  
  if ($arrayify and not ref $value) {
    $value = [$value];
  }
  
  #print STDERR "format_value (arrayified): ";
  #p @_;

  my $type_alias = {
                    # These are really just aliases for arrays of float
                    'point' => 'float[3]',
                    'vector' => 'float[3]',
                    'normal' => 'float[3]',
                    'color' => 'float[3]',
                   };
  
  if (not defined $type) {
    if (looks_like_number $value) {
      $type = 'float';
    } else {
      $type = 'string';
    }
  }

  if (exists $type_alias->{$type}) {
    $type = $type_alias->{$type};
  }
  
  if ($type eq 'bool' and not ref $value) {
    $value = $value ? 'true' : 'false';
    $type = 'string';
  }

  #print STDERR "format_value (guessed, aliased, booled): ";
  #p @_;

  if ($type =~ m/^(.*?)\[(\d+)\]$/) {
    if (not ref $value) {
      die "In format_value, $value is not an array (expected $type)";
    }
    if (@$value != $2) {
      die "In format_value, $value does not have correct number of elements for $type";
    }
    $type = $1;
  }
  
  if (ref $value eq 'ARRAY') {
    return '[' . (join ' ', map {format_value($_, $type)} @$value) . ']';
  }
  
  if (not defined $type) {
    if (looks_like_number $value) {
      $type = 'float';
    } else {
      $type = 'string';
    }
  }

  if ($type eq 'string') {
    return sprintf '"%s"', $value;
  } elsif ($type eq 'float') {
    return sprintf '%f', $value;
  } else {
    return $value;
  }
}

# General grammar of a thingy.
# http://www.luxrender.net/wiki/Scene_file_format_1.0#Components_of_a_.lxs_file
# doesn't give a good name for "thingy".
sub output_thingy {
  my $indent_level = shift @_;
  my $indent_str = ' ' x $indent_level;

  my $identifier = ucfirst(shift @_);
  my @extras;
  my $attributes;
  my @children;

  # Because dog forbid that we not have annyoing special cases...
  if ($identifier eq 'Transform') {
    return sprintf "${indent_str}Transform [%s]\n", join ' ', map {format_value $_, 'float'} @_;
  }
  
  for my $param (@_) {
    if (not ref $param and not $attributes) {
      push @extras, $param;
    } elsif (ref $param eq 'HASH') {
      $attributes = $param;
    } else {
      # If we've already got the attributes, it must be a child (which must be an array ref?).
      push @children, $param;
    }
  }

  $attributes ||= {};
  
  if ($identifier =~ m/^(.*)Begin$/) {
    $attributes->{_ending} = $1."End";
  }

  my $ending = delete $attributes->{_ending} || "";
  
  my $ret = qq<$indent_str$identifier>;
  for my $extra (@extras) {
    $ret .= " ".format_value($extra);
  }

  if (%$attributes or @children) {
    $ret .= "\n";
  }
  for my $k (sort keys %$attributes) {
    my $v = $attributes->{$k};
    my ($type, $value) = @$v;
    my $fmt_val = format_value($value, $type, 1);
    
    $ret .= qq<$indent_str "$type $k" $fmt_val\n>;
  }

  for my $child (@children) {
    $ret .= output_thingy($indent_level+1, @$child);
  }

  if ($ending) {
    $ret .= "$indent_str$ending\n"
  }
  $ret .= "\n" if not $ret =~ m/\n$/ms;
  
  return $ret;
}

sub output_lxs {
  my ($bit) = @_;

  my $ret = '';

  # Fixme: try "hybrid" later.
  $ret .= output_thingy(0, Renderer => 'sampler');
  $ret .= output_thingy(0, Sampler => 'metropolis',
                        {usevariance => [bool => 1],
                         noiseaware => [bool => 1]});
  
  $ret .= output_thingy(0, Accelerator => 'qbvh');
  $ret .= output_thingy(0, SurfaceIntegrator => 'bidirectional',
                        {eyedepth => [integer => 4],
                         lightdepth => [integer => 4],
                         lightraycount => [integer => 1],
                         lightpathstrategy => [string => 'auto'],
                         lightstrategy => [string => 'auto'],
                        });
  
  $ret .= output_thingy(0, 'VolumeIntegrator' => 'none');
  
  $ret .= output_thingy(0, LookAt => 0, 4, 0,   0, 3, 0,   0, 0, 1);

  $ret .= output_thingy(0, Camera => 'perspective',
                        {fov => [float => 49],
                         #screenwindow => [float => [-1, 1, -0.5625, 0.5625]],
                         autofocus => [bool => 1],
                         shutteropen => [float => 0],
                         shutterclose => [float => 1],
                        });
  
  
  $ret .= output_thingy(0, 'Film', 'fleximage',
                        {
                         xresolution => [integer => 1920],
                         yresolution => [integer => 1080],
                         filename => [string => "$bit-simulation"],
                         
                         # Write an exr file, and keep it nicely raw
                         write_exr => [bool => 1],
                         write_exr_applyimaging => [bool => undef],
                         write_exr_gamutclamp => [bool => undef],
                         write_exr_channels => [string => 'RGBA'],
                         
                         write_png => [bool => 1],
                         write_png_channels => [string => 'RGB'],
                         
                         write_resume_flm => [bool => 1],
                         
                         # After we get to N samples per pixel,
                         # ignore too-bright outliers.
                         outlierrejection_k => [integer => 0.1],
                         
                         # After we get to M samples per pixel, stop
                         haltspp => [integer => 10],

                         # We don't want to auto-expose each texture seperately, so give fixed tone-mapping parameters here.
                         # These were done by going to luxrenderer on white-simulation, tone mapping / kernel / linear, hitting
                         # estimate settings, and tweaking from there.

                         tonemapkernel => [string => 'linear'],
                         linear_sensitivity => [float => 800],
                         linear_exposure => [float => 20],
                         linear_fstop => [float => 5.6],
                         linear_gamma => [float => 1],
                        }
                       );
  
  $ret .= output_thingy(0, 'WorldBegin', {},
                        ['MakeNamedMaterial', 'boring',
                         {
                          # http://www.luxrender.net/wiki/LuxRender_Materials_Matte
                          type => [string => 'matte'],
                          Kd => [color => [0.6, 0.6, 0.6]],
                          sigma => [float => 0]
                         }
                        ],
                        
                        [AttributeBegin => {},
                         [Transform => (1.000000000000000, 0.000000000000000, 0.000000000000000, 0.000000000000000,
                                        0.000000000000000, 1.000000000000000, 0.000000000000000, 0.000000000000000,
                                        0.000000000000000, 0.000000000000000, 1.000000000000000, 0.000000000000000,
                                        0.000000000000000, 0.000000000000000, 0.000000000000000, 1.000000000000000)],
                         [NamedMaterial => 'boring'],
                         [Shape => 'sphere',
                          {radius => ['float', 1]}
                         ],
                        ],
                        
                         [AttributeBegin => {},
                          [Transform => (1, 0, 0, 0,
                                         0, 1, 0, 0,
                                         0, 0, 1, 0,
                                         0, 0, 0, 1)],
                          [NamedMaterial => 'boring'],
                          [Shape => 'disk',
                           {radius => ['float' => 100],
                            height => ['float' => -1],
                           }
                          ]
                         ],

                        [TransformBegin => {},
                         [Transform => (  0.707106769084930, -0.707106769084930,  0.000000000000000, 0.000000000000000,
                                         -0.000000030908620, -0.000000030908620, -1.000000000000000, 0.000000000000000,
                                          0.707106769084930,  0.707106769084930, -0.000000043711388, 0.000000000000000,
                                          2.000000000000000,  2.000000000000000,  0.000000000000000, 1.000000000000000) ],
                         [Rotate => 180, 0, 1, 0],
                         [LightGroup => 'default'],
                         [LightSource => 'projection',
                          {mapname => [string => "$bit-texture.png"]},
                         ]
                        ]
                       );

  return $ret;
}

