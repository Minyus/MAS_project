extensions [ csv table ]
breed [ stations station]
breed [ trucks truck]
stations-own [
_simulated_num_bikes_available
_simulated_num_docks_available

_station_id
_station_latitude
_station_longitude
_capacity
_initial_num_bikes_available
_total_departure_count
_total_arrival_count
_departure_cumulative_relative_frequency
_arrival_cumulative_relative_frequency
_forecast
]

trucks-own [
tcap
cargo
pick
drop
quantity
]

globals [
  table_data_source
  table_data
  panel_data_source
  panel_data
  vals_list
  vals_list_length
  panel_data_pointer
  panel_data_length

  time_previous
  time_step_completed?

  station_id_source
  station_id_target
  interstation_distance
  interstation_distance_rank

  station_id_source_list
  station_id_target_list
  interstation_distance_list
  interstation_distance_rank_list

  time
  station_id
  station_latitude
  station_longitude
  capacity
  initial_num_bikes_available
  total_departure_count
  total_arrival_count
  departure_cumulative_relative_frequency
  arrival_cumulative_relative_frequency

  station_id_list
  station_latitude_list
  station_longitude_list
  capacity_list
  initial_num_bikes_available_list
  total_departure_count_list
  total_arrival_count_list
  departure_cumulative_relative_frequency_list
  arrival_cumulative_relative_frequency_list

  num_bike_users
  last_station_departed
  last_station_arrived

  simulated_out_of_bikes_count
  simulated_out_of_docks_count

  sim_timestep_counter
  sim_timestep_to_panel_timestep
  sim_elapsed_hours
  sim_elapsed_days
]


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  ca
  reset-ticks
  init-lists
  set time_step_completed? false
  set panel_data_length 0
  set-default-shape stations "dot"
  setup-table
  setup-panel
  output-print ( word "[" date-and-time "] Set up complete." )
end

to init-lists
  set	station_id_source_list	[]
  set	station_id_target_list	[]
  set	interstation_distance_list	[]
  set	interstation_distance_rank_list	[]

  set	station_id_list	[]
  set	station_latitude_list	[]
  set	station_longitude_list	[]
  set	capacity_list	[]
  set	initial_num_bikes_available_list	[]
  set	total_departure_count_list	[]
  set	total_arrival_count_list	[]
  set	departure_cumulative_relative_frequency_list	[]
  set	arrival_cumulative_relative_frequency_list	[]
end

to setup-table
  set table_data_source "Boston_Hubway_Interstation_Distance.csv"
  set table_data read-data table_data_source
  ifelse empty? table_data
    [ output-print word "Failed to read " table_data_source ]
    [
    output-print word "Succeeded to read " table_data_source
      if is-string? last first table_data
         [set table_data butfirst table_data] ;; remove header row
      ]
  foreach table_data [ ? ->
    set	station_id_source	item	0	?
    set	station_id_target	item	1	?
    set	interstation_distance	item	2	?
    set	interstation_distance_rank	item	3	?

    set	station_id_source_list	lput	station_id_source	station_id_source_list	
    set	station_id_target_list	lput	station_id_target	station_id_target_list	
    set	interstation_distance_list	lput	interstation_distance	interstation_distance_list	
    set	interstation_distance_rank_list	lput	interstation_distance_rank	interstation_distance_rank_list	
  ]
end

to setup-panel
  set panel_data_source "Boston_Hubway_Station_CRF_2012-09.csv"
  set panel_data read-data panel_data_source
  ifelse empty? panel_data
    [ output-print word "Failed to read " panel_data_source ]
    [
    output-print word "Succeeded to read " panel_data_source
      if is-string? last first panel_data
         [set panel_data butfirst panel_data] ;; remove header row
      set panel_data_pointer -1
      set panel_data_length length panel_data
      set vals_list first panel_data
      set vals_list_length length vals_list
    go

      ]
end

to-report read-data [ file_name ]
;; create rows as an empty list
  let rows []
;; user-file reports false if no file is selected
;; if file_name is not a csv file, expect a run-time error.
  if file_name != false [
    set panel_data_source file_name
    file-open file_name
 ;; csv:from-file creates a list of lists
    set rows csv:from-file file_name
    file-close ]
  report rows
end


to set-forecast
  ;; setup forecast per station with hour as key (military time)
  file-open "Boston_Hubway_Forecast.csv"
  let h csv:from-row file-read-line
  ifelse empty? h
    [ output-print word "Failed to read " panel_data_source ]
    [
  while [ not file-at-end? ] [
    let row csv:from-row file-read-line
    ask stations with[_station_id = first row] [ table:put _forecast (item 1 row) (item 2 row)]
  ]
    file-close ]
end

to go
  set sim_timestep_to_panel_timestep ( 60 / sim_timestep_minutes )
  if sim_timestep_counter = 0 [ update-station-agents update-trucks] ;; initialize trucks on top of stations
  set sim_timestep_counter ( sim_timestep_counter + 1 )  ;; increment the counter
  if sim_timestep_counter >= sim_timestep_to_panel_timestep [ set sim_timestep_counter 0 ]
  user-trip-submodel
  ;;rebalancing-submodel
  update-station-status
  ;; rebalancing animation and steps toggled by rebalance global switch
  if rebalance [
    if sim_timestep_counter > 0 and sim_timestep_counter < 20 [ ask trucks [face pick fd (distance pick) / 19] ]
    if sim_timestep_counter = 20 [pickup_bikes]
    if sim_timestep_counter > 20 and sim_timestep_counter < 50 [ ask trucks [face drop fd (distance drop) / 29] ]
    if sim_timestep_counter = 50 [dropoff_bikes]
  ]
  tick
  set sim_elapsed_hours ( ticks / sim_timestep_to_panel_timestep )
  set sim_elapsed_days ( sim_elapsed_hours / 24 )
  if sim_elapsed_days >= days_to_simulate [
    output-print ( word "[" date-and-time "] Simulation of " sim_elapsed_days " days completed." )
    stop
  ]
end

to update-trucks
  ;; initialize trucks
  ifelse not any? trucks [
    create-trucks num_trucks [
      set tcap 20
      set cargo 0
      set color green
      set shape "car"
      set size 1
      move-to station 63
      set_pickup_destination ;; set initial pickup point
      set_dropoff_destination ;; set initial dropoff point
    ]
  ]
  [
    ;; update pickup and dropoff points at every time step 0
    if rebalance [
      set_pickup_destination
      set_dropoff_destination
    ]
  ]
end

to update-station-agents
  set time_step_completed? false
  while [ not time_step_completed? ] [
     fetch-each-station-panel-data
  ]

  foreach station_id_list [ ? ->
    if not any? stations with [ _station_id = ? ] [
      create-stations 1 [
        set _station_id ?
        set _simulated_num_bikes_available -1
        set _simulated_num_docks_available -1
        set _forecast table:make ;; create dict of forecasts / hour
      ]
    ]
    ask stations with [ _station_id = ? ] [
      let i (position ? station_id_list)

      set	_station_latitude	item i	station_latitude_list
      set	_station_longitude	item i	station_longitude_list
      set	_capacity	item i	capacity_list
      set	_initial_num_bikes_available	item i	initial_num_bikes_available_list
      set	_total_departure_count	item i	total_departure_count_list
      set	_total_arrival_count	item i	total_arrival_count_list
      set	_departure_cumulative_relative_frequency	item i	departure_cumulative_relative_frequency_list
      set	_arrival_cumulative_relative_frequency	item i	arrival_cumulative_relative_frequency_list

      setxy ( (_station_longitude * 100 ) + 7109) ( (_station_latitude * 100 ) - 4235)
      if _simulated_num_bikes_available = -1 [
        set _simulated_num_bikes_available _initial_num_bikes_available
        set _simulated_num_docks_available ( _capacity - _simulated_num_bikes_available )
      ]
    ]
  ]
  if [table:length _forecast] of station 0 = 0 [ set-forecast ] ;; initialize stations with forecast data
end

to fetch-each-station-panel-data
  ;; first check if should stop
  ;; A. prevent runtime error if setup was not run first
  if panel_data_length = -1 [output-print "no file selected" stop]
  ;; B. prevent runtime error if at end of file or no file selected
  if panel_data_pointer >= panel_data_length [output-print "end of file [1]" stop]
  ;; C. stop the stream if at end of file after increment
  set panel_data_pointer panel_data_pointer + 1
  if panel_data_pointer >= panel_data_length[ output-print "end of file [2]" stop]
  ;; not at end of file, so continue

  if time_step_completed? [
    init-lists
    set time_step_completed? false
  ]
  if panel_data_pointer > 0 [
    set	station_id_list	lput	station_id	station_id_list
    set	station_latitude_list	lput	station_latitude	station_latitude_list
    set	station_longitude_list	lput	station_longitude	station_longitude_list
    set	capacity_list	lput	capacity	capacity_list
    set	initial_num_bikes_available_list	lput	initial_num_bikes_available	initial_num_bikes_available_list
    set	total_departure_count_list	lput	total_departure_count	total_departure_count_list
    set	total_arrival_count_list	lput	total_arrival_count	total_arrival_count_list
    set	departure_cumulative_relative_frequency_list	lput	departure_cumulative_relative_frequency	departure_cumulative_relative_frequency_list
    set	arrival_cumulative_relative_frequency_list	lput	arrival_cumulative_relative_frequency	arrival_cumulative_relative_frequency_list
  ]

  set time_previous time
  get-next-record

  ifelse panel_data_pointer > 0
    [set time_step_completed? (time != time_previous) ]
    [set time_step_completed? false]
end

to get-next-record
  set vals_list item panel_data_pointer panel_data
  map-panel-data-columns
end

to map-panel-data-columns
set	time	item	0	vals_list
set	station_id	item	1	vals_list
set	station_latitude	item	2	vals_list
set	station_longitude	item	3	vals_list
set	capacity	item	4	vals_list
set	initial_num_bikes_available	item	5	vals_list
set	total_departure_count	item	6	vals_list
set	total_arrival_count	item	7	vals_list
set	departure_cumulative_relative_frequency	item	8	vals_list
set	arrival_cumulative_relative_frequency	item	9	vals_list
end

to  update-station-status
  ask stations [
    set color white
    if _simulated_num_bikes_available < 3 [ set color red ]
    if _simulated_num_docks_available < 3 [ set color blue ]
  ]
end

;;; User Trip Submodel follows:

to user-trip-submodel
  set num_bike_users random-num-bike-users-to-appear
  repeat num_bike_users [
    use-a-bike
  ]
end

to-report random-num-bike-users-to-appear
  let c first total_departure_count_list ;; first, last, one-of (total_departure_count is the same for all the stations)
  let m ( c / sim_timestep_to_panel_timestep ) ;;
  set num_bike_users random-poisson m
  report num_bike_users
end

to use-a-bike
  rent-a-bike-at-a-station
  return-a-bike-at-a-station
end

to rent-a-bike-at-a-station
  ;; Reference: CS603 Week05 slide "Uncertainty Simulating Data from Frequency Bins"
  let p position-threshold ( random-float 1 ) departure_cumulative_relative_frequency_list
  let sid item p station_id_list
  ;; If the station has an available bike, then rent it. Otherwise, search the closest station with an available bike recursively.
  find-a-staion-with-an-available-bike sid -1
end

to return-a-bike-at-a-station
  ;; Reference: MAS Week05 slide "Uncertainty Simulating Data from Frequency Bins"
  let p position-threshold ( random-float 1 ) arrival_cumulative_relative_frequency_list
  let sid item p station_id_list
  ;; If the station has an available dock, then return the bike to it. Otherwise, search the closest station with an available dock recursively.
  find-a-staion-with-an-available-dock sid -1
end

to find-a-staion-with-an-available-bike [ _sid _n ]
  let _sid_target _sid
  if _n >= 0 [ set _sid_target nth-closest-station _sid _n ]
  if _n = 0 [ set simulated_out_of_bikes_count ( simulated_out_of_bikes_count + 1 ) ] ;;
  ask stations with [ _station_id = _sid_target ] [
  ifelse _simulated_num_bikes_available > 0 ;; If there is no bikes available
    [
      set last_station_departed _sid_target ;;
      set _simulated_num_bikes_available ( _simulated_num_bikes_available - 1 )
      set _simulated_num_docks_available ( _capacity - _simulated_num_bikes_available )
    ]
    [
      if (_n <= ( count stations - 3 ) ) ;; Avoid trying to find non-exsisting stations
      [ find-a-staion-with-an-available-bike _sid (_n + 1) ] ;; Recursion
    ]
  ]
end

to find-a-staion-with-an-available-dock [ _sid _n ]
  let _sid_target _sid
  if _n >= 0 [ set _sid_target nth-closest-station _sid _n ]
  if _n = 0 [ set simulated_out_of_docks_count ( simulated_out_of_docks_count + 1 ) ] ;;
  ask stations with [ _station_id = _sid_target ] [
  ifelse _simulated_num_docks_available > 0 ;; If there is no docks available
    [
      set last_station_arrived _sid_target ;;
      set _simulated_num_docks_available ( _simulated_num_docks_available - 1 )
      set _simulated_num_bikes_available ( _capacity - _simulated_num_docks_available )
    ]
    [
      if (_n <= ( count stations - 3 ) ) ;; Avoid trying to find non-exsisting stations
      [ find-a-staion-with-an-available-dock _sid (_n + 1) ] ;; Recursion
    ]
  ]
end

to-report position-threshold [ _item _list ]
  ;; return the position (index) that the exceeds the threshold of _item
  let position_threshold length ( filter [ ? -> ? < _item ] _list )
  report position_threshold
end

to-report nth-closest-station [ _station_id_source _n ]
  ;; return the station_id that is _n-th closest to _station_id_source
  ;; _n = 0 means the closesest, _n = 1 means the 2nd closest, and so on.
  let _sid_positions positions _station_id_source station_id_source_list
  ;output-print _sid_positions
  let _rank_positions positions _n interstation_distance_rank_list
  ;output-print word _station_id_source _n
  let _position first ( intersect _sid_positions _rank_positions ) ;; first, last, one-of
  let sid item _position station_id_target_list
  report sid
end

to-report positions [ _item _list ]
  ;; return all the positions (multiple version of "position" function)
  report filter [? -> item ? _list = _item]
                n-values (length _list) [? -> ?]
end

to-report intersect [list_a list_b]
  ;; return the common elements of the 2 input lists
   report (filter [ ? -> member? ? list_b ] list_a)
end

;;; Rabalancing Submodel follows:

;;to rebalancing-submodel
  ;; To do: add rebalancing submodel here.
;;end

;; action to pickup bikes from pickup point and update values
to pickup_bikes
  ask trucks [
  move-to pick
  let tmp (tcap - cargo) ;; actual capacity of truck
  let sav [_simulated_num_bikes_available] of pick ;; num bikes available for pickup
  let truquant 0
  ifelse sav >= quantity [set truquant quantity] [set truquant sav] ;; set quantity for pickup

  ;; update truck cargo as well as station avaiable bikes and docks
  ifelse tmp >= truquant
    [ set cargo truquant
    ask pick
    [set _simulated_num_bikes_available (_simulated_num_bikes_available - truquant)
     set _simulated_num_docks_available (_simulated_num_docks_available + truquant)]
    ]
    [set cargo tmp
    ask pick
      [set _simulated_num_bikes_available (_simulated_num_bikes_available - tmp)
       set _simulated_num_docks_available (_simulated_num_docks_available + tmp)]
    ]
;;  ask pick [ifelse tmp >= truquant
;;      [set _simulated_num_bikes_available (_simulated_num_bikes_available - truquant)
;;       set _simulated_num_docks_available (_simulated_num_docks_available + truquant)]
;;      [set _simulated_num_bikes_available (_simulated_num_bikes_available - tmp)
;;       set _simulated_num_docks_available (_simulated_num_docks_available + tmp)] ]
  set color cyan ;; color for dropping off
  ]
end

to dropoff_bikes
  ask trucks [
  move-to drop
  let sav [_capacity - _simulated_num_bikes_available] of drop ;; actual capacity to take in bikes
  let truquant 0
  ifelse sav >= cargo [set truquant cargo] [set truquant sav] ;; set quantity for dropoff

  ;; update station available bikes and docks
  ask drop
    [set _simulated_num_bikes_available (_simulated_num_bikes_available + truquant)
     set _simulated_num_docks_available (_simulated_num_docks_available - truquant)]
  set cargo (cargo - truquant) ;; update truck cargo
  set color green ;; color for pickup
  ]
end

to set_pickup_destination
  let t (get_time + 1) ;; next time step
  if t = 24 [set t 0]
  let station_set get_supply t ;; get station-set with most supply at next time step

  ;; assign closest truck for each supply station
  foreach [who] of trucks [? -> let st_id [who] of station_set with-min[distance truck ?]
    ask truck ? [set pick station first st_id set quantity ceiling (([table:get _forecast t] of station first st_id) * -1)]
    ask station_set [ set station_set station_set with[self != station first st_id]]
  ]
end

to set_dropoff_destination
  let t (get_time + 1) ;; next time step
  if t = 24 [set t 0]
  let station_set get_demand t ;; get station-set with most demand at next time step

  ;; assign closest truck for each demand station
  foreach [who] of trucks [? -> let st_id [who] of station_set with-min[distance truck ?]
    ask truck ? [set drop station first st_id set quantity ceiling (([table:get _forecast t] of station first st_id) * -1)]
    ask station_set [ set station_set station_set with[self != station first st_id]]
  ]
end

to-report get_demand [t]
  ;;let top stations with-min[table:get _forecast t] ;;sort-on [who]
  ;;ifelse count top > num_trucks [report n-of num_trucks top] [report top]
  let top sublist (sort-on [table:get _forecast t] stations) 0 num_trucks ;; _forecast is hour : demand
  report turtle-set top
end

to-report get_supply [t]
  ;;let top stations with-max[table:get _forecast t] ;;sort-on [(- who)]
  ;;ifelse count top > num_trucks [report n-of num_trucks top] [report top]
  let top sublist (sort-on [table:get _forecast t] stations) 0 num_trucks ;; _forecast is hour : demand
  report turtle-set top
end

;; time calculator
to-report get_time
  let factor 1
  if ticks > 1440 [set factor floor (ticks / 1440)]
  report floor ((ticks mod (factor * 1440)) / 60)
end
@#$#@#$#@
GRAPHICS-WINDOW
-5
110
358
474
-1
-1
27.31
1
8
1
1
1
0
1
1
1
-6
6
-6
6
0
0
1
ticks
30.0

BUTTON
10
10
73
43
NIL
setup
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

BUTTON
80
10
205
43
go once (1 time step)
go
NIL
1
T
OBSERVER
NIL
G
NIL
NIL
1

BUTTON
220
10
307
43
go forever
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

OUTPUT
0
530
990
680
11

PLOT
370
370
790
514
simulated cumulative out of bikes and docks count
NIL
NIL
0.0
1.0
0.0
1.0
true
false
"" ""
PENS
"out of bikes" 1.0 0 -5298144 true "" "plot simulated_out_of_bikes_count"
"out of docks" 1.0 0 -13345367 true "" "plot simulated_out_of_docks_count"

MONITOR
370
10
485
55
NIL
panel_data_pointer
17
1
11

MONITOR
490
10
607
55
NIL
panel_data_length
17
1
11

MONITOR
490
65
610
110
time to
time
17
1
11

MONITOR
370
65
490
110
time from
time_previous
17
1
11

MONITOR
370
160
487
205
number of stations
count stations
17
1
11

PLOT
370
250
575
370
histogram
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" "set-plot-x-range 0 30\nset-plot-y-range 0 20\nset-histogram-num-bars 20"
PENS
"default" 1.0 0 -16777216 true "" "histogram [ _simulated_num_bikes_available ] of stations"

MONITOR
800
380
977
425
NIL
simulated_out_of_bikes_count
17
1
11

MONITOR
800
450
982
495
NIL
simulated_out_of_docks_count
17
1
11

MONITOR
370
205
555
250
total number of bikes
sum [ _simulated_num_bikes_available ] of stations
17
1
11

CHOOSER
80
50
200
95
sim_timestep_minutes
sim_timestep_minutes
1 2 5 10 30 60
0

SLIDER
215
60
365
93
days_to_simulate
days_to_simulate
1
30
7.0
1
1
days
HORIZONTAL

MONITOR
615
65
735
110
NIL
sim_elapsed_hours
0
1
11

MONITOR
735
65
850
110
NIL
sim_elapsed_days
0
1
11

TEXTBOX
20
480
340
536
Note: Each dot represents a bike docking station. Red means the # bikes < 3. Blue means the # docks < 3. 
11
0.0
1

SWITCH
380
115
487
148
rebalance
rebalance
0
1
-1000

SLIDER
510
120
682
153
num_trucks
num_trucks
1
20
3.0
1
1
NIL
HORIZONTAL

BUTTON
5
50
75
83
go (2000)
repeat 2000 [go]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

CS603 Team 08's Bike Sharing System (BSS) simulation program to find better rebalancing methods.

## HOW IT WORKS

During set up, read 2 CSV files: 

CSV file 1: interstation distance table data
CSV file 2: station status panel data (aggregated by hour level)

For each time step (1 minute in default) in each hour slot, read the CSV file 2 contents (panel) accordingly to obtain 2 sets of information:

Info 1: the total number of user trips in the hour slot
Info 2: the cumulative relative frequency (CRF) for departure (renting) and arrival (returning) for each station in the hour slot

Generate a random variable based on Poisson distribution with the mean parameter as the total number of user trips in the time step calculated from Info 1 to determine the simulated number of user trips.

For each simulated user trip, generate 2 random variables based on uniform distribution between 0 and 1, compare with Info 2 to determine the station the user rented and the station the user returned.

Please see  CS603 Team 08's proposal slides and
CS603 Week05 slide "Uncertainty Simulating Data from Frequency Bins" for details.

If there is no available bike at the station to rent or no available dock at the station to return, find the closest station with an available bike to rent or a dock to return using the CSV file 2 content (table). This recursive algorithm is to make sure that no bikes will disappear.

The events when there is no avaialble bike at the chosen station to rent and the events when there is no available dock at the chosen station to return are counted. The objective is to find a rebalancing method that minimizes these 2 metrics.


## HOW TO USE IT

Click "Setup" and either "Go once" or "Go forever"


## CREDITS AND REFERENCES

Sequential timeseries using CSV
http://modelingcommons.org/browse/one_model/4990#model_tabs_browse_info

find lists intersection in NetLogo
https://stackoverflow.com/questions/26928738/find-lists-intersection-in-netlogo

CS603 Week05 slide "Uncertainty Simulating Data from Frequency Bins"
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
1
@#$#@#$#@
