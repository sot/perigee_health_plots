; startup procedure for IDL
; Robert Cameron November 1990
;
; modified for IDL version 2, March 1991
; modified for CfA, IDL version 3, March 1993
; modified by TLA, July 1997

!Y.STYLE = 2+16
set_plot, 'ps'
device, ysize = 25.4, yoffset = 1.905
set_plot, 'x'
;device, retain=2
;beep = string(7B)

;!path = '/home/aldcroft/Aspect/IDL_utils:' + $
;        '/home/rac/idl:/home/rac/idl/ball:' + $
;        expand_path('+/soft/idl/idl_4/resource') + ':' + $
;        expand_path('+/soft/idl/idl_4/user_contrib') + ':' + !path

;  COSMOS
;!path = '/home/rac/idl:/home/rac/idl/ball:' + $
;        '/home/aldcroft/Aspect/IDL_utils:' + !path

;  DRONGO
!path = '/proj/sot/ska/idl:'+'/home/aldcroft/idl/rac:' + $
  '/data/axafd/rac/idl:/data/axafd/rac/idl/ball:' + $
  '/home/aldcroft/Aspect/IDL_utils:' + $
  '/home/aldcroft/Aspect/IDL_utils/flt:' + $
  '/data2/local/lib/idl/astro/pro:' + $
  !path

print, ' '
print, '***** Executed startup.pro ******'
print, ' '

pi = double(!pi)
r2a = 180.0d0*3600.d0/!pi
a2r = 1.0d0/r2a
r2d = 180.0d0/!pi
d2r = !pi/180.0d0

RED_colormap   = bytarr(255)+255
GREEN_colormap = bytarr(255)+255
BLUE_colormap  = bytarr(255)+255

RED_colormap[0:8] =   [0, 255, 255,   0,   0, 255, 204, 255,   170]
GREEN_colormap[0:8] = [0, 255,   0, 255,   0, 255, 102,  170,   170]
BLUE_colormap[0:8] =  [0, 255,   0,   0, 255,   0, 204,  170,  255]

color_values = BLUE_colormap * '10000'xl + GREEN_colormap * '100'xl + RED_colormap

; For 8-bit pseudocolor.  This works well with both 'x' and 'ps'
    defsysv, '!col', {  $
                       black:0, $
                       white  :1, $
                       ps_black:1, $
                       ps_white  :0, $
                       red    :2, $
                       green  :3, $
                       blue   :4, $
                       yellow :5, $
                       magenta:6, $
                       light_red :7, $
                       light_blue :8 $
                     }

; Something from
;
; http://groups.google.com/groups?hl=en&lr=&ie=UTF-8&oe=UTF-8&selm=39401193.37E3E98C%40ssec.wisc.edu&rnum=3

if !version.os_family eq 'unix' then device, true_color=24
window, /free, /pixmap, colors=-10
wdelete, !d.window
device, decomposed=0, retain=2
device, get_visual_depth=depth
; print, 'Display depth: ', depth
; print, 'Color table size: ', !d.table_size

    set_plot,'x'
;    device, pseudo_color=8
;    device,decompose=0

    TVLCT, RED_colormap, GREEN_colormap, BLUE_colormap

; For 24-bit true color.  This doesn't work for 'ps'

;defsysv, '!col', {  $
;                       black  :color_values[0], $
;                       white  :color_values[1], $
;                       red    :color_values[2], $
;                       green  :color_values[3], $
;                       blue   :color_values[4], $
;                       yellow :color_values[5], $
;                       magenta:color_values[6], $
;                       light_red :color_values[7], $
;                       light_blue :color_values[8] $
;                       }
;    set_plot,'x'
;    device,true_color=24
;    device,decompose=1

END
