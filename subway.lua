
api_version = 4

Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require("lib/way_handlers")
Relations = require("lib/relations")
find_access_tag = require("lib/access").find_access_tag
limit = require("lib/maxspeed").limit
Utils = require("lib/utils")
Measure = require("lib/measure")

function setup()
  return {
    properties = {
      max_speed_for_map_matching     = 180/3.6, -- speed conversion to m/s
      -- For routing based on duration, but weighted for preferring certain roads
      weight_name                    = 'routability',
      -- For shortest duration without penalties for accessibility
      -- weight_name                     = 'duration',
      -- For shortest distance without penalties for accessibility
      -- weight_name                     = 'distance',
      process_call_tagless_node      = false,
      u_turn_penalty                 = 60 * 2, -- 2 minutes to change cab
      continue_straight_at_waypoint  = true,
      use_turn_restrictions          = false,
      left_hand_driving              = false,
      traffic_light_penalty          = 2,
      turn_duration                  = 20,
      max_angle                      = 30,
      
      secondary_speed                = 10,
      speed                          = 10,
    },
    
    default_mode              = mode.driving,
    default_speed             = 10,
    
    oneway_handling           = true,
    side_road_multiplier      = 0.8,
    turn_penalty              = 22.5,
    speed_reduction           = 0.5,
    turn_bias                 = 1.075,
    cardinal_directions       = false,
    
    -- Size of the vehicle, to be limited by physical restriction of the way
    vehicle_height = 3.0, -- in meters, 2.0m is the height slightly above biggest SUVs
    vehicle_width = 2.5, -- in meters, ways with narrow tag are considered narrower than 2.2m
    
    -- Size of the vehicle, to be limited mostly by legal restriction of the way
    vehicle_length = 40.8, -- in meters, 4.8m is the length of large or family car
    vehicle_weight = 30000, -- in kilograms
    
    -- a list of suffixes to suppress in name change instructions. The suffixes also include common substrings of each other
    suffix_list = {
      'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'North', 'South', 'West', 'East', 'Nor', 'Sou', 'We', 'Ea'
    },
    
    barrier_whitelist = Set {
      'cattle_grid',
      'border_control',
      'toll_booth',
      'sally_port',
      'gate',
      'lift_gate',
      'no',
      'entrance',
      'height_restrictor',
      'arch'
    },
    
    access_tag_whitelist = Set {
      'yes',
      'motorcar',
      'motor_vehicle',
      'vehicle',
      'destination',
      'permissive',
      'designated',
      'hov'
    },
    
    access_tag_blacklist = Set {
      'no',
      'agricultural',
      'forestry',
      'emergency',
      --'psv',
      --'customers',
      'private',
      --'delivery',
    },
    
    -- tags disallow access to in combination with highway=service
    service_access_tag_blacklist = Set {
      'private',
    },
    --
    restricted_access_tag_list = Set {
      'private',
      'delivery',
      --    'destination',
      --    'customers',
    },
    --
    access_tags_hierarchy = Sequence {
      --    'motorcar',
      --    'motor_vehicle',
      --    'vehicle',
      --    'access'
    },
    --
    service_tag_forbidden = Set {
      'emergency_access',
      'yard',
      'spur'
    },
    
    restrictions = Sequence {
      'motorcar',
      'motor_vehicle',
      'vehicle'
    },
    --
    classes = Sequence {
      'highspeed',
      'toll',
      'motorway', 
      'ferry', 
      'restricted',
      'tunnel',
      -- 'not_electric'
    },
    
    -- classes to support for exclude flags
    excludable = Sequence {
      Set {'highspeed'},
      Set {'toll'},
      Set {'motorway'},
      Set {'ferry'},
    },
    
    avoid = Set {
      'area',
      -- 'toll',    -- uncomment this to avoid tolls
      'reversible',
      'impassable',
      'hov_lanes',
      'steps',
      'construction',
      'proposed'
    },
    speeds = Sequence {},
    
    service_penalties = {
      alley             = 0.5,
      parking           = 0.5,
      parking_aisle     = 0.5,
      driveway          = 0.5,
      ["drive-through"] = 0.5,
      ["drive-thru"] = 0.5
    },
    
    restricted_highway_whitelist = Set {
      'motorway',
      'motorway_link',
      'trunk',
      'trunk_link',
      'primary',
      'primary_link',
      'secondary',
      'secondary_link',
      'tertiary',
      'tertiary_link',
      'residential',
      'living_street',
      'unclassified',
      'service'
    },
    
    construction_whitelist = Set {
      'no',
      'widening',
      'minor',
    },
    
    route_speeds = {
      ferry = 5,
      shuttle_train = 10
    },
    
    bridge_speeds = {
      movable = 5
    },
    
    
    -- List only exceptions
    maxspeed_table = {},
    
    relation_types = Sequence {
      "route"
    },
    
    -- classify highway tags when necessary for turn weights
    highway_turn_classification = {
    },
    
    -- classify access tags when necessary for turn weights
    access_turn_classification = {
    }
  }
  
end


function ternary ( cond , T , F )
  if cond then return T else return F end
end


function process_node(profile, node, result, relations)
  local railway = node:get_value_by_key("railway")
  result.barrier = (
    railway and (railway == "buffer_stop" or railway == "derail")
  )
  result.traffic_lights = false
end

function process_way(profile, way, result, relations)
  local data = {
    highway = way:get_value_by_key('highway'),
    bridge = way:get_value_by_key('bridge'),
    route = way:get_value_by_key('route'),

    -- prefetch tags
    railway = way:get_value_by_key("railway"),
    embedded_rails = way:get_value_by_key("embedded_rails"),
    metro = way:get_value_by_key("metro"),
    usage = way:get_value_by_key("usage"),
    service = way:get_value_by_key("service"),

    
    electified = way:get_value_by_key("electified"),
    trafic_mode = way:get_value_by_key("railway:traffic_mode"),
  }
  --
  -- Remove everything that is not railway
  if not data.railway then
    return
  end
  
  -- Remove everything that is not a rail, a turntable, a traverser
  if 
    data.railway ~= 'subway'
    -- and
    -- data.railway ~= 'construction' 
  then
    return
  end

  if (
    data.usage == "military" or
    data.usage == "tourism" or
    data.usage == 'industrial'
  ) then
    return
  end


  local is_secondary = (
    data.service == "siding" or
    data.service == "spur" or
    data.service == "yard"
  )

  if (is_secondary) then
    return
  end

  result.forward_speed = profile.properties.speed
  result.backward_speed = profile.properties.speed

  local handlers = Sequence {
    -- set the default mode for this profile. if can be changed later
    -- in case it turns we're e.g. on a ferry
    WayHandlers.default_mode,

    -- check various tags that could indicate that the way is not
    -- routable. this includes things like status=impassable,
    -- toll=yes and oneway=reversible
    WayHandlers.blocked_ways,
    WayHandlers.avoid_ways,
    WayHandlers.handle_height,
    WayHandlers.handle_width,
    WayHandlers.handle_length,
    WayHandlers.handle_weight,

    -- determine access status by checking our hierarchy of
    -- access tags, e.g: motorcar, motor_vehicle, vehicle
    -- WayHandlers.access,

    -- check whether forward/backward directions are routable
    WayHandlers.oneway,

    -- check a road's destination
    WayHandlers.destinations,

    -- check whether we're using a special transport mode
    WayHandlers.ferries,
    WayHandlers.movables,

    -- handle service road restrictions
    WayHandlers.service,

    -- compute speed taking into account way type, maxspeed tags, etc.
    WayHandlers.speed,
    WayHandlers.maxspeed,
    WayHandlers.penalties,

    -- compute class labels
    WayHandlers.classes,

    -- handle turn lanes and road classification, used for guidance
    WayHandlers.turn_lanes,
    WayHandlers.classification,

    -- handle various other flags
    WayHandlers.roundabouts,
    WayHandlers.startpoint,
    WayHandlers.driving_side,

    -- set name, ref and pronunciation
    WayHandlers.names,

    -- set weight properties of the way
    WayHandlers.weights,

    -- set classification of ways relevant for turns
    WayHandlers.way_classification_for_turn
  }


  WayHandlers.run(profile, way, result, data, handlers, relations)

  if profile.cardinal_directions then
    Relations.process_way_refs(way, relations, result)
  end

end

function process_turn(profile, turn)
  -- Use a sigmoid function to return a penalty that maxes out at turn_penalty
  -- over the space of 0-180 degrees.  Values here were chosen by fitting
  -- the function to some turn penalty samples from real driving.
  local turn_penalty = profile.turn_penalty
  local turn_bias = turn.is_left_hand_driving and 1. / profile.turn_bias or profile.turn_bias

  if turn.has_traffic_light then
      turn.duration = profile.properties.traffic_light_penalty
  end

  if turn.number_of_roads > 2 or turn.source_mode ~= turn.target_mode or turn.is_u_turn then
    if turn.angle >= 0 then
      turn.duration = turn.duration + turn_penalty / (1 + math.exp( -((13 / turn_bias) *  turn.angle/180 - 6.5*turn_bias)))
    else
      turn.duration = turn.duration + turn_penalty / (1 + math.exp( -((13 * turn_bias) * -turn.angle/180 - 6.5/turn_bias)))
    end

    if turn.is_u_turn then
      turn.duration = turn.duration + profile.properties.u_turn_penalty
    end
  end

  -- for distance based routing we don't want to have penalties based on turn angle
  if profile.properties.weight_name == 'distance' then
     turn.weight = 0
  else
     turn.weight = turn.duration
  end

  if profile.properties.weight_name == 'routability' then
      -- penalize turns from non-local access only segments onto local access only tags
      if not turn.source_restricted and turn.target_restricted then
          turn.weight = constants.max_turn_weight
      end
  end
end

return {
  setup = setup,
  process_way = process_way,
  process_node = process_node,
  process_turn = process_turn
}
