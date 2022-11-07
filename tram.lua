
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
      weight_name                    = 'routability',
      left_hand_driving              = false,
      u_turn_penalty                 = 60 * 2, -- 2 minutes to change cab
      turn_duration                  = 20,
      continue_straight_at_waypoint  = true,
      max_angle                      = 30,

      secondary_speed                = 30,
      speed                          = 160,
    },

    default_mode              = mode.driving,
    default_speed             = 10,

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
        --'emergency',
        --'psv',
        --'customers',
        --'private',
        --'delivery',
    },

      -- tags disallow access to in combination with highway=service
    --service_access_tag_blacklist = Set {
    --    'private'
    --},
    --
    --restricted_access_tag_list = Set {
    --    'private',
    --    'delivery',
    --    'destination',
    --    'customers',
    --},
    --
    --access_tags_hierarchy = Sequence {
    --    'motorcar',
    --    'motor_vehicle',
    --    'vehicle',
    --    'access'
    --},
    --
    --service_tag_forbidden = Set {
    --    'emergency_access'
    --},
    --
    --restrictions = Sequence {
    --    'motorcar',
    --    'motor_vehicle',
    --    'vehicle'
    --},
    --
    classes = Sequence {
        'highspeed',
        'toll', 'motorway', 'ferry', 'restricted', 'tunnel'
    },

    -- classes to support for exclude flags
    excludable = Sequence {
        Set {'highspeed'},
        Set {'toll'},
        Set {'motorway'},
        Set {'ferry'}
        --Set {'not_electric'},
    },
}

end


function ternary ( cond , T , F )
    if cond then return T else return F end
end


function process_node(profile, node, result, relations)
    local railway = node:get_value_by_key("railway")
    result.barrier = (
        railway == "buffer_stop" or
        railway == "derail"
    )
    result.traffic_lights = false
end

function process_way(profile, way, result, relations)
    local data = {
        railway = way:get_value_by_key("railway"),
        metro = way:get_value_by_key("metro"),
        service = way:get_value_by_key("service"),
        usage = way:get_value_by_key("usage"),
        name = way:get_value_by_key("name"),
        ref = way:get_value_by_key("ref"),
        maxspeed = way:get_value_by_key("maxspeed"),
        gauge = way:get_value_by_key("gauge"),

        oneway = way:get_value_by_key("oneway"),
        preferred = way:get_value_by_key("railway:preferred_direction"),

        highspeed = way:get_value_by_key("highspeed") == "yes",
        electified = way:get_value_by_key("electified"),
        trafic_mode = way:get_value_by_key("railway:traffic_mode"),
    }
    --
    ---- Remove everything that is not railway
    --if not data.railway then
    --    return
    ---- Remove military and tourism rails
    --elseif (
    --    data.usage == "military" or
    --    --data.usage == "tourism" or
    --    data.usage == 'industrial'
    --) then
    --    return
    --end

    -- Remove everything that is not a rail, a turntable, a traverser
    if not (
        data.railway == 'tram' or
        data.railway == 'light_rail' or
        data.railway == 'tram_level_crossing'
    ) then
        return
    end

    --if data.metro and data.metro == 'yes' then
    --    return
    --end

    local is_secondary = (
        data.service == "siding" or
        data.service == "spur" or
        data.service == "yard"
    )


    local default_speed = ternary(is_secondary, profile.properties.secondary_speed, profile.properties.speed)
    local speed = ternary(data.maxspeed, data.maxspeed, default_speed)

    result.forward_speed = speed
    result.backward_speed = speed
    --
    result.forward_mode = mode.driving
    result.backward_mode = mode.driving
    --
    result.forward_rate = 1
    result.backward_rate = 1
    --
    --if data.oneway == "no" or data.oneway == "0" or data.oneway == "false" then
    --    -- both ways are ok, nothing to do
    --elseif data.oneway == "-1" then
    --    -- opposite direction
    --    result.forward_mode = mode.inaccessible
    --elseif data.oneway == "yes" or data.oneway == "1" or data.oneway == "true" then
    --    -- oneway
    --    result.backward_mode = mode.inaccessible
    --end
    --
    --if data.preferred == "forward" then
    --    result.backward_rate = result.backward_rate - 0.3
    --elseif data.preferred == "backward" then
    --    result.forward_rate = result.forward_rate - 0.3
    --end
    --
    result.name = ternary(data.name, data.name, data.ref)
    --
    --if data.highspeed then
    --    result.forward_classes["highspeed"] = true
    --    result.backward_classes["highspeed"] = true
    --    result.forward_rate = result.forward_rate - 0.2
    --    result.backward_rate = result.backward_rate - 0.2
    --end
    --
    --if data.is_secondary then
    --    result.forward_rate = result.forward_rate - 0.1
    --    result.backward_rate = result.backward_rate - 0.1
    --end
    --
    if (
        data.electified == "no" or
        data.electified == "rail"
    ) then
        result.forward_classes["not_electric"] = true
        result.backward_classes["not_electric"] = true
    end
    --
    ---- Restrict secondary to be used only at start or end
    ---- result.forward_restricted = is_secondary
    ---- result.backward_restricted = is_secondary
    --

end

function process_turn(profile, turn)
    --if math.abs(turn.angle) >  profile.properties.max_angle then
    --    weight = 0.0
    --    duration = 0.0
    --    return
    --end
    if turn.number_of_roads > 2 then
        turn.duration =  profile.properties.turn_duration
    end
    if turn.is_u_turn then
      turn.duration = turn.duration + profile.properties.u_turn_penalty
    end
end

return {
  setup = setup,
  process_way = process_way,
  process_node = process_node,
  process_turn = process_turn
}
