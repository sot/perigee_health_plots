

# red, green, blue, magenta, cyan, orange, purple... maybe
plot_colors = ['#ff0000', '#00ff00', '#0000ff',
               '#ff00ff', '#00ffff', '#ff6600',
               '#6600ff' ]

# break up telem in chunks of time_interval seconds
time_interval = 20.0

# and require min_samples per time_interval
min_samples = 5

# if telem values exceed these limits, cut the values
telem_chomp_limits = { 'dac' : { 'max': 550 },
                       'ccd_temp' : {'min' : -35,
                                     'max' : 50 },
                       'aca_temp' : {'max' : 50,
                                     'min' : 5 },
                       }

# if telem values exceed these limits just warn about it
telem_limits = {'ccd_temp': {'max': -14.0}}

# plot stuff, just ranges now
dac_plot = { 'ylim' : (460,515) }
dacvsdtemp_plot = { 'ylim' : (460,515),
                      'xlim' : (37,40) }
aca_temp_plot = {'ylim': (20, 28)}
ccd_temp_plot = {'ylim': (-19, -13)}



# at some point, create routine to do this more cleanly from characteristics

#products['dac'] = aca0[7]['HD3TLM76'][ok[7]] * 256. + aca0[7]['HD3TLM77'][ok[7]]
#products['time'] = aca0[7]['TIME'][ok[7]]
##products['h066'] = aca0[0]['HD3TLM66'] * 256 + aca0[0]['HD3TLM67']
##products['h072'] = aca0[0]['HD3TLM72'] * 256 + aca0[0]['HD3TLM73']
##products['h074'] = aca0[0]['HD3TLM74'] * 256 + aca0[0]['HD3TLM75']
##products['h174'] = aca0[1]['HD3TLM74'] * 256 + aca0[1]['HD3TLM75']
##products['h176'] = aca0[1]['HD3TLM76'] * 256 + aca0[1]['HD3TLM77']
##products['h262'] = aca0[2]['HD3TLM62'] * 256 + aca0[2]['HD3TLM63']
##products['h264'] = aca0[2]['HD3TLM64'] * 256 + aca0[2]['HD3TLM65']
##products['h266'] = aca0[2]['HD3TLM66'] * 256 + aca0[2]['HD3TLM67']
##products['h272'] = aca0[2]['HD3TLM72'] * 256 + aca0[2]['HD3TLM73']
##products['h274'] = aca0[2]['HD3TLM74'] * 256 + aca0[2]['HD3TLM75']
##products['h276'] = aca0[2]['HD3TLM76'] * 256 + aca0[2]['HD3TLM77']
#products['aca_temp'] = aca0[7]['HD3TLM73'][ok[7]] * (1/256.) +  aca0[7]['HD3TLM72'][ok[7]]
#products['ccd_temp'] = ( (aca0[6]['HD3TLM76'][ok[6]] * 256.) + (aca0[6]['HD3TLM77'][ok[6]] - 65536. )) / 100.
