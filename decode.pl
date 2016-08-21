#!/usr/bin/perl
use Imager;
use 5.12.0;
use Math::PlanePath::HilbertCurve;
use POSIX 'ceil';

my $data;

my $path = Math::PlanePath::HilbertCurve->new;

my $texture_width = 400;
my $texture_height = 300;
my ($n_min, $n_max) = $path->rect_to_n_range(0, 0 => $texture_width-1, $texture_height-1);
if ($n_min != 0) {
    die "Fixme: n-range doesn't start at 0";
}
my $bits = ceil(log($n_max - $n_min) / log(2));

say "Texture size: $texture_width x $texture_height x $bits bits";


my $img = Imager->new(file => "white-simulation.png") or die;
$img = $img->convert(preset=>'grey');
my $white_values = [];

say "Reading white reference";
for my $y (0..$img->getheight-1) {
    my $scanline = $img->getscanline(y=>$y, type => '8bit');
    # Make sure the array is the correct overall size.
    $data->[$img->getwidth][$y] ||= 0;
    for my $x (0..$img->getwidth-1) {
        # NB: While channels is 1, that only means that there is 1 *occupied* channel.  There's still space in the scanline for 4.
        $white_values->[$x][$y] = vec $scanline, 4*$x, 8;
    }
}

my ($width, $height);

for my $bit (0..$bits-1) {
    say "reading image for $bit";
    my $img = Imager->new(file => "$bit-simulation.png") or die;
    $img = $img->convert(preset=>'grey');

    $width = $img->getwidth;
    $height = $img->getheight;

    my $bitval = 1<<$bit;

    my $channels = $img->getchannels;
    print "After fiddling, channels=$channels\n";

    for my $y (0..$height-1) {
        my $scanline = $img->getscanline(y=>$y, type => '8bit');
        if (0) {
            #my $print = join '', map {sprintf "%02x", ord $_} split //, $scanline;
            #print "$print\n";
        }
        # Make sure the array is the correct overall size.
        $data->[$width-1][$y] ||= 0;
        for my $x (0..$width-1) {
            # NB: While channels is 1, that only means that there is 1 *occupied* channel.  There's still space in the scanline for 4.
            my $v = vec $scanline, 4*$x, 8;

            my $white = $white_values->[$x][$y];

            if ($white > 0) {
                #printf "%d / %d = %f\n", $v, $white, $v/$white;
                
                if ($v / $white > 0.75) {
                    $data->[$x][$y] |= $bitval;
                }
            }
        }
    }
}

my $img = Imager->new(xsize => $width, ysize => $height);

print "Generating output image\n";

for my $x (0..$width-1) {
    my $scancol = $data->[$x];
    for my $y (0..$height-1) {
        my $val = $scancol->[$y];
        my ($texture_x, $texture_y) = $path->n_to_xy($val);
        if ($val) {
            say "$val: ($texture_x, $texture_y)";
        }
        my $r = 255 * $texture_x / $texture_width;
        my $g = 255 * $texture_y / $texture_height;
        my $b = 0; #($texture_y / $texture_height) * 255;
        $img->setpixel(x=>$x, y=>$y, color => [$r, $g, $b]);
    }
}

print "Writing output image\n";

$img->write(file => "output.png", type => 'png') or die;

