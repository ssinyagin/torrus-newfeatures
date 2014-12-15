# RRDtool graph Colors and Lines Profile.
# You are encouraged to create your own copy and reference it
# with $Torrus::Renderer::stylingProfile in your torrus-siteconfig.pl
# or better define your amendments in Torrus::Renderer::stylingProfileOverlay

# Stanislav Sinyagin <ssinyagin@yahoo.com>
# Shawn Ferry <sferry at sevenspace dot com> <lalartu at obscure dot org>

%Torrus::Renderer::graphStyles =
    (
     'SingleGraph'     => {
         'color' => '##blue',
         'line'  => 'LINE2'
         },     
     'SingleGraphMax'  => {  # MAX value graph on top of the Average
         'color' => '##cornflowerblue',
         'line'  => 'LINE1'
         },
     'HWBoundary'     => {
         'color' => '##red',
         'line'  => 'LINE1'
         },
     'HWFailure'      => {
         'color' => '##moccasin'
         },
     'HruleMin'       => {
         'color' => '##darkmagenta'
         },
     'HruleNormal'    => {
         'color' => '##seagreen'
         },
     'HruleMax'       => {
         'color' => '##darkmagenta'
         },
     'HruleWarn'       => {
         'color' => '##darkorange'
         },
     'HruleCrit'       => {
         'color' => '##crimson'
         },
     'BpsIn'          => {
         'color' => '#01ca00',
         'line'  => 'AREA'
         },
     'BpsOut'         => {
         'color' => '##blue',
         'line'  => 'LINE2'
         },
     'BpsInMax'          => {
         'color' => '#b7ea8c',
         'line'  => 'AREA'
         },
     'BpsOutMax'         => {
         'color' => '#017eb5',
         'line'  => 'LINE1'
         },

     'BusinessDay'    => {
         'color' => '##white',
         'line'  => 'AREA'
         },
     'Evening'        => {
         'color' => '##mintcream',
         'line'  => 'AREA'
         },
     'Night'          => {
         'color' => '##lavender',
         'line'  => 'AREA'
         },

     # Common Definitions
     # Using generic names allows the "generic" value to be
     # changed without editing every instance
     'in'       => {
         'color'   => '##green',
         'line'    => 'AREA'
         },
     'out'      => {
         'color'   => '##blue',
         'line'    => 'LINE2'
         },

     'nearend'       => {
         'color'   => '##green',
         'line'    => 'LINE2'
         },
     'farend'      => {
         'color'   => '##blue',
         'line'    => 'LINE2'
         },

     'maxvalue'       => {
         'color'   => '##darkseagreen',
         'line'    => 'AREA'
         },
     'currvalue'      => {
         'color'   => '##blue',
         'line'    => 'LINE2'
         },

     'totalresource'  => {
         'color'   => '##palegreen',
         'line'    => 'AREA'
         },
     'resourceusage'  => {
         'color'   => '##blue',
         'line'    => 'AREA'
         },
     'resourcepartusage'  => {
         'color'   => '##crimson',
         'line'    => 'AREA'
         },

     # convenient definitions one - ten, colors that
     # "work" in a single graph
     'one'      => {'color'   => '##green'},
     'two'      => {'color'   => '##blue'},
     'three'    => {'color'   => '##red'},
     'four'     => {'color'   => '##gold'},
     'five'     => {'color'   => '##seagreen'},
     'six'      => {'color'   => '##cornflowerblue'},
     'seven'    => {'color'   => '##crimson'},
     'eight'    => {'color'   => '##darkorange'},
     'nine'     => {'color'   => '##darkmagenta'},
     'ten'      => {'color'   => '##orangered'},

     # Numbered palette to make dynamically assembled stacked charts
     # dark28 and accent8 color schemes, from
     # http://bloodgate.com/perl/graph/manual/att_colors.html
     'clr1'     => {'color'   => '#1b9e77'},
     'clr2'     => {'color'   => '#d95f02'},
     'clr3'     => {'color'   => '#7570b3'},
     'clr4'     => {'color'   => '#e7298a'},
     'clr5'     => {'color'   => '#66a61e'},
     'clr6'     => {'color'   => '#e6ab02'},
     'clr7'     => {'color'   => '#a6761d'},
     'clr8'     => {'color'   => '#666666'},
     'clr9'     => {'color'   => '#7fc97f'},
     'clr10'    => {'color'   => '#beaed4'},
     'clr11'    => {'color'   => '#fdc086'},
     'clr12'    => {'color'   => '#ffd92f'},
     'clr13'    => {'color'   => '#386cb0'},
     'clr14'    => {'color'   => '#f0027f'},
     'clr15'    => {'color'   => '#bf5b17'},
     
     # definitions for combinatorial graphing

     #RED
     'red1'     => {
         'color'  => '##red',
         'line'   => 'AREA',
     },
     'red2'     => {
         'color'  => '##red25',
         'line'   => 'STACK',
     },
     'red3'     => {
         'color'  => '##red50',
         'line'   => 'STACK',
     },
     'red4'     => {
         'color'  => '##red75',
         'line'   => 'STACK',
     },

     #GREEN
     'green1'     => {
         'color'   => '##green',
         'line'    => 'AREA',
     },
     'green2'     => {
         'color'   => '##green25',
         'line'    => 'STACK',
     },
     'green3'     => {
         'color'   => '##green50',
         'line'    => 'STACK',
     },
     'green4'     => {
         'color'   => '##green75',
         'line'    => 'STACK',
     },

     #BLUE
     'blue1'     => {
         'color'   => '##blue',
         'line'    => 'AREA',
     },
     'blue2'     => {
         'color'   => '##blue25',
         'line'    => 'STACK',
     },
     'blue3'     => {
         'color'   => '##blue50',
         'line'    => 'STACK',
     },
     'blue4'     => {
         'color'   => '##blue75',
         'line'    => 'STACK',
     },
     );

# Place for extra RRDtool graph arguments
# Example: ( '--color', 'BACK#D0D0FF', '--color', 'GRID#A0A0FF' );
@Torrus::Renderer::graphExtraArgs = ();

1;
