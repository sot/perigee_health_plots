pro aca_health, dirname, ps_outfile
; Script to read temperatures and levels stuck in HDR3 aca 0 telemetry
; and make plots

cd, dirname

columns=['imgraw', 'quality', 'time', 'TEMPCCD', 'TEMPHOUS','TEMPPRIM','TEMPSEC','HD3TLM62','HD3TLM63','HD3TLM64','HD3TLM65','HD3TLM66','HD3TLM67','HD3TLM72','HD3TLM73','HD3TLM74','HD3TLM75','HD3TLM76','HD3TLM77']
ccdmcols = ['time', 'quality', 'COBSRQID' ]


obs0 = { PLOTDEF, COLOR: !col.black, SYMBOL: 1}
obs1 = { PLOTDEF, COLOR: !col.light_red, SYMBOL: 1}
obs2 = { PLOTDEF, COLOR: !col.blue, SYMBOL: 1}
obs3 = { PLOTDEF, COLOR: !col.red, SYMBOL: 1}
obs4 = { PLOTDEF, COLOR: !col.light_blue, SYMBOL: 1}
obs5 = { PLOTDEF, COLOR: !col.magenta, SYMBOL: 1}


obscnt = 6

plotarray = [ obs0, obs1, obs2, obs3, obs4, obs5 ]


first = 1
first_obsid = 1

time_interval = 20.
min_samples = 4

; define data structure
result = { HEALTH, TIME: 0.0D, ACA_TEMP: 0.0D, CCD_TEMP: 0.0D, DAC: 0.0D, H066: 0.0D, H072: 0.0D, H074: 0.0D, H174: 0.0D, H176: 0.0D, H262: 0.0D, H264: 0.0D, H266: 0.0D, H272: 0.0D, H274: 0.0D, H276: 0.0D, OBSID: ' ', PLOTSYMBOL: 0, PLOTCOLOR: 0 }
obsid_legend = { OBSLEGEND, OBSID: ' ', PLOTCOLOR: 0, PLOTSYMBOL: 0}

data0 = 0
data1 = 0
data2 = 0
data6 = 0
data7 = 0

spawn, 'ls -1 ccdm*fits*', ccdm0_files

; cobsrqid is a uint, so use unsigned flag
ccdm = mrdfits( ccdm0_files[0], 1, columns=ccdmcols, /silent, /unsigned)
for i = 1, n_elements(ccdm0_files)-1 do begin
    temp = mrdfits( ccdm0_files[i], 1, columns=ccdmcols, /silent, /unsigned)
    ccdm = [ccdm, temp]
endfor

obsid = 0
obsid_count = -1

for slot = 0, 7 do begin
    spawn, 'ls -1 acaf*_'+ $
    strtrim(string(slot),2)+'_*.fits*', files

    garg = 0
    for i = 0, n_elements(files)-1 do begin
        test = mrdfits(files[i],1,columns=columns,/silent)
        nsize = size(test.imgraw)
        if (nsize[1] eq 8 and nsize[2] eq 8) then begin
            if garg eq 0 then temp = [files[i]] else $
              temp = [temp,files[i]]
            garg = 1
            
        endif
    endfor
    if n_elements(temp) ne 0 then begin
        files = temp
        dat = mrdfits(files[0],1,columns=columns,str='bar',/silent) 
        okdat = where( dat.quality eq 0 )
        dat = dat[okdat]
        for i = 1, n_elements(files)-1 do begin
            dat1 = mrdfits(files[i],1, columns=columns,str='bar',/silent)
            okdat = where( dat1.quality eq 0 )
            dat1 = dat1[okdat]
            dat = [dat,dat1]
        endfor
        switch slot of
            0: BEGIN
                slot0 = dat
                data0 = 1
                break
            END
            1: BEGIN
                slot1 = dat
                data1 = 1
                break
            END
            2: BEGIN
                slot2 = dat
                data2 = 1
                break
            END
            6: BEGIN
                slot6 = dat
                data6 = 1
                break
            END
            7: BEGIN
                slot7 = dat
                data7 = 1
                break
            END
            else:
        endswitch
        
    endif
endfor
if (data0 and data1 and data2 and data6 and data7) then begin
    starttime = max([ min(slot0.time), min(slot1.time), min(slot2.time), min(slot6.time), min(slot7.time) ])
;        print,starttime-pstart
    endtime = min([ max(slot0.time), max(slot1.time), max(slot2.time), max(slot6.time), max(slot7.time) ])
    n_time_intervals = floor((endtime-starttime)/time_interval)
    for t=0, n_time_intervals-1 do begin
        range_start = starttime + (time_interval * t)
        range_end = range_start + time_interval
        ok_slot0 = where( (slot0.time ge range_start) and ( slot0.time lt range_end ) )
        ok_slot1 = where( (slot1.time ge range_start) and ( slot1.time lt range_end ) )
        ok_slot2 = where( (slot2.time ge range_start) and ( slot2.time lt range_end ) )
        ok_slot6 = where( (slot6.time ge range_start) and ( slot6.time lt range_end ) )
        ok_slot7 = where( (slot7.time ge range_start) and ( slot7.time lt range_end ) )
        if ( ( n_elements(ok_slot0) ge min_samples) and ( n_elements(ok_slot1) ge min_samples ) and ( n_elements(ok_slot2) ge min_samples ) and ( n_elements(ok_slot6) ge min_samples ) and ( n_elements(ok_slot7) ge min_samples )) then begin 
            dac = median(slot7[ok_slot7].HD3TLM76*256.0 + slot7[ok_slot7].HD3TLM77)
            h066 = median(slot0[ok_slot0].HD3TLM66*256.0 + slot0[ok_slot0].HD3TLM67)
            h072 = median(slot0[ok_slot0].HD3TLM72*256.0 + slot0[ok_slot0].HD3TLM73)
            h074 = median(slot0[ok_slot0].HD3TLM74*256.0 + slot0[ok_slot0].HD3TLM75)
            h174 = median(slot1[ok_slot1].HD3TLM74*256.0 + slot1[ok_slot1].HD3TLM75)
            h176 = median(slot1[ok_slot1].HD3TLM76*256.0 + slot1[ok_slot1].HD3TLM77)
            h262 = median(slot2[ok_slot2].HD3TLM62*256.0 + slot2[ok_slot2].HD3TLM63)
            h264 = median(slot2[ok_slot2].HD3TLM64*256.0 + slot2[ok_slot2].HD3TLM65)
            h266 = median(slot2[ok_slot2].HD3TLM66*256.0 + slot2[ok_slot2].HD3TLM67)
            h272 = median(slot2[ok_slot2].HD3TLM72*256.0 + slot2[ok_slot2].HD3TLM73)
            h274 = median(slot2[ok_slot2].HD3TLM74*256.0 + slot2[ok_slot2].HD3TLM75)
            h276 = median(slot2[ok_slot2].HD3TLM76*256.0 + slot2[ok_slot2].HD3TLM77)
            aca_temp =  median(slot7[ok_slot7].HD3TLM73/256.0 + slot7[ok_slot7].HD3TLM72)
            ccd_temp =  median(((slot6[ok_slot6].HD3TLM76)*256.+(slot6[ok_slot6].HD3TLM77)-65536.)/100.)
            time =  median(slot6[ok_slot6].time)
            curr_result = result
            curr_result.dac = dac
            curr_result.h066 = h066 
            curr_result.h072 = h072
            curr_result.h074 = h074
            curr_result.h174 = h174
            curr_result.h176 = h176
            curr_result.h262 = h262
            curr_result.h264 = h264
            curr_result.h266 = h266
            curr_result.h272 = h272
            curr_result.h274 = h274
            curr_result.h276 = h276
            curr_result.aca_temp = aca_temp
            curr_result.ccd_temp = ccd_temp
            curr_result.time = time
            poss_ccdm = max( where(ccdm.time lt time) )
            curr_result.obsid = string(ccdm[poss_ccdm].cobsrqid, format='(i5)')
            if ( curr_result.obsid ne obsid ) then begin
                obsid_count++
                print, curr_result.obsid
                obsid = curr_result.obsid
                curr_result.plotcolor = plotarray[obsid_count mod obscnt].color
                curr_result.plotsymbol = plotarray[obsid_count mod obscnt].symbol

                if (first_obsid) then begin
                    obsid_list = obsid_legend
                    obsid_list.obsid = curr_result.obsid
                    obsid_list.plotsymbol = curr_result.plotsymbol
                    obsid_list.plotcolor = curr_result.plotcolor
                    first_obsid = 0
                endif else begin
                    temp_obsid = obsid_legend
                    temp_obsid.obsid = curr_result.obsid
                    temp_obsid.plotsymbol = curr_result.plotsymbol
                    temp_obsid.plotcolor = curr_result.plotcolor
                    obsid_list = [ obsid_list, temp_obsid]
                endelse

            endif

            curr_result.plotcolor = plotarray[obsid_count mod obscnt].color
            curr_result.plotsymbol = plotarray[obsid_count mod obscnt].symbol

            if (first) then begin
                master_result = curr_result
                first = 0
            endif else begin
                master_result = [ master_result, curr_result ]
            endelse
        endif
    endfor


endif

pstart = min(master_result.time)
pstop = max(master_result.time)

;fit = poly_fit( aca_temp-ccd_temp, dac, 2)
fit = [ 154.250, -2.32916, 0.282743 ]
xvals = indgen(23*100)/100.+20

yfit = poly( xvals, fit )
;print, yfit
;
;
;

cnt=n_elements(master_result)
;;window, 1
;if (plot) then begin
    set_plot, 'ps'
    device, file=ps_outfile, /encapsul, /color, xsize=10, ysize=6, /inches, /landscape
    !p.multi = [0,2,2]
;endif

plot, [0], [0], /nodata, xtitle='seconds from radmon disable', ytitle='ACA temp (C)', yrange=[18,20], xrange=[ 0 , (pstop-pstart) + 10000 ], xstyle=1
for i = 0, cnt-1 do begin
    oplot, [ master_result[i].time - pstart], [master_result[i].aca_temp], psym=master_result[i].plotsymbol, color=master_result[i].plotcolor
end
legend, obsid_list.obsid, psym=obsid_list.plotsymbol, color=obsid_list.plotcolor
plot, [0], [0], /nodata,  xtitle='seconds from radmon disable ', ytitle='CCD temp (C)', yrange=[-22,-18], xrange=[0, (pstop-pstart)+ 10000], xstyle=1
for i = 0, cnt-1 do begin
    oplot, [ master_result[i].time - pstart ], [master_result[i].ccd_temp], psym=master_result[i].plotsymbol, color=master_result[i].plotcolor
end
;legend, obsid_list.obsid, psym=obsid_list.plotsymbol, color=obsid_list.plotcolor

temprange = master_result.aca_temp - master_result.ccd_temp
plot,[0],[0], /nodata,   xtitle='seconds from radmon disable', ytitle='TEC DAC Control Level', yrange=[min(master_result.dac)-10 , 520], xrange=[0, (pstop-pstart) + 10000], xstyle=1, ystyle=1
for i = 0, cnt-1 do begin
    oplot, [ master_result[i].time -  pstart ], [master_result[i].dac], psym=master_result[i].plotsymbol, color=master_result[i].plotcolor
end
;legend, obsid_list.obsid, psym=obsid_list.plotsymbol, color=obsid_list.plotcolor

plot, [0], [0], /nodata, xstyle=1, ystyle=1, psym=2, xrange=[min(temprange)-.2, max(temprange)+.2], yrange=[min(master_result.dac)-10, 520], xtitle='ACA temp - CCD temp (C)', ytitle='TEC DAC Control Level'
oplot, xvals, yfit, color=!col.black
oplot, [24 , 43], [500, 500], linestyle=2 ;dashed
oplot, [24 , 43], [511, 511], linestyle=0, color=!col.red ;dashed
;;, charsize=2.5, charthick=4
;;oplot, [24, 32], [24*plotln[1]+plotln[0], 32*plotln[1]+plotln[0]]
for i = 0, cnt-1 do begin
    oplot, [master_result[i].aca_temp-master_result[i].ccd_temp], [master_result[i].dac], psym=master_result[i].plotsymbol, color=master_result[i].plotcolor
end
;legend, obsid_list.obsid, psym=obsid_list.plotsymbol, color=obsid_list.plotcolor
;;oplot, [36], [ 36*plotln[1]+plotln[0] ], psym=2, color=!col.red,
;;symsize=3
;oplot, [38.8], [ poly( 38.8, fit) ], psym=2, color=!col.red
;;xyouts, 35.5, (425)+25, "-20C est.", align=.3
;;xyouts, 35.5, (425)-32, "(CCD at -20C)", align=0.5
;;print, 37.3, poly( 37.3, fit)
;; limit=where(  gt 510.8 and yfit lt 511.2 )
;;print, limit
;;print, xvals[limit], yfit[limit]
;A = findgen(16) * (!PI*2/16.)
;USERSYM,COS(A),SIN(A)
;oplot, [40.26], [511], psym=8, color=!col.red
;
;if (plot) then begin
    device, /close
    set_plot, 'x'
    !p.multi = 0
;endif
;

cd,'..'
end

