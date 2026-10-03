-- ---- Colour palette (brush index, R, G, B) ----
set_brush_color(0, 0.0, 0.0, 0.0) -- black
set_brush_color(1, 1.0, 1.0, 1.0) -- white
set_brush_color(2, 0.5, 0.0, 0.0) -- red
set_brush_color(3, 0.0, 0.1, 0.4) -- blue
set_brush_color(4, 0.6, 0.4, 0.2) -- brown (wooden plate)
set_brush_color(5, 1.0, 0.8, 0.0) -- yellow (backlash probe, stands out against everything else)

-- Every emit() uses a name from this table instead of a bare number
local brush = {
  driving_gear  = 2,
  driven_gear   = 1,
  shaft         = 3,
  shim          = 0,
  driving_cap   = 1, -- white cap on the red gear
  driven_cap    = 2, -- red cap on the white gear
  handle        = 0,
  extra_handle  = 2,
  wooden_plate  = 4,
  intersection  = 5,
}

-- ---- Gear constants ----
local x_min                      = -0.3 -- minimum profile shift coefficient (undercut limit)
local x_max                      = 1.0  -- maximum profile shift coefficient
local h_a_coef                   = 1.25 -- addendum of the generating rack = dedendum of the gear (ISO 53: 1.25*m)

-- ---- Hardware constants [mm] (match the printed prototype) ----
local spring_compressed_h        = 8    -- compressed spring height under the driving gear
local mesh_min_overlap           = 1    -- gears stay engaged by at least this much at zero axial offset
local shim_thickness             = 3    -- shim thickness
local shim_tolerance             = 0.1  -- radial clearance shim <-> shaft
local key_width                  = 3    -- anti-rotation key on the shim / slot in the driven shaft
local shaft_tolerance            = 0.1  -- radial clearance shaft <-> gear bore
local thread_tolerance           = 0.1  -- radial clearance of the external thread
local thread_offset              = 0.5  -- radial wobble of the thread profile (thread depth ~ 2*thread_offset)
local thread_steps_per_mm        = 10   -- thread sections per mm of length
local thread_deg_per_step        = 10   -- rotation per section
local thread_deg_per_mm          = thread_steps_per_mm * thread_deg_per_step -- 100 deg/mm -> 3.6 mm pitch
local driving_shaft_tolerance    = 0.1  -- clearance between driving gear recess and shaft extra (hub)
local hub_margin                 = 3    -- minimum wall between hub recess and tooth root
local driving_shaft_protrusion   = 6    -- driving shaft length beyond the face width
local driving_thread_length      = 5    -- threaded length on the driving shaft
local driving_cap_lift           = 2    -- driving cap sits this far above the gear top
local driving_cap_cylinder_height = 8   -- height of the ring under the driving cap nut
local driving_cap_nut_height     = 5    -- thread height of the driving cap nut
local cap_gap                    = 0.5  -- gap between upper shim and driven cap nut
local mount_height               = 5    -- height of the screw-down mounting block
local mount_gap                  = 15   -- gap between the two mounting blocks
local screw_thread_height        = 11   -- wood screw: threaded length
local screwHole_dia              = 1.9  -- wood screw: pilot hole diameter
local screwHead_dia              = 4.8  -- wood screw: countersunk head diameter
local handle_pin_height          = 11   -- snap-pin length
local handle_hexagon_w           = 10   -- handle hexagon width across flats
local handle_hexagon_h           = 10   -- handle hexagon height
local handle_margin              = 8    -- handle axis sits this far inside the smallest root circle
local pinhole_depth              = 10   -- depth of the snap-pin hole in the driving gear
local tolerance                  = 0.3  -- snap-pin clearance
local wood_length                = 210.0 -- wooden base board (A5 footprint)
local wood_breadth               = 148.0
local wood_height                = 9.0

-- ============================================================
-- SECTION 2: UI PARAMETERS
-- ============================================================
-- All widgets are declared here so they appear in a sensible order in the IceSL panel.

local res          = ui_number("Resolution", 10, 5, 50)     -- Controls mesh resolution for all curve samplings
local show_threads = ui_bool("Show threads (slow)", false)  -- helical threads vs plain cylinders
local advanced     = ui_bool("Advanced gear parameters", false)

-- Returns the default in the simple view, or a slider in the advanced view
local function param(kind, label, default, min, max)
  if not advanced then return default end
  if kind == "int" then return ui_number(label, default, min, max) end
  return ui_scalar(label, default, min, max)
end

-- ---- Gear geometry ----
local m           = param("real", "Module", 4.0, 1.0, 10.0)                    -- Gear module [mm]
local alpha_n_deg = param("int", "Normal Pressure Angle (deg)", 20, 16, 24)  -- Normal pressure angle in degrees

local alpha_n_rad = math.rad(alpha_n_deg)

-- ---- Minimum tooth count to prevent undercut: z_min = 2 (1 - x_min) / sin^2(alpha_n) ----
local sin_alpha_n = math.sin(alpha_n_rad)
local zmin        = math.ceil(2 * (1 - x_min) / (sin_alpha_n * sin_alpha_n))

local z_driving   = param("int", "Number of Teeth-Driving Gear", math.max(22, zmin), zmin, 40)
local z_driven    = param("int", "Number of Teeth-Driven Gear", math.max(22, zmin), zmin, 40)
local b           = param("real", "Face Width (mm)", 15.0, 5.0, 30.0)         -- Axial face width [mm]

-- ---- Profile shifts of Driving Gear ----
local x_coef_bottom_driving = param("real", "Profile Shift Coefficient Bottom-Driving Gear", x_max, x_min, x_max)
local x_coef_top_driving    = param("real", "Profile Shift Coefficient Top-Driving Gear", x_min, x_min, x_max)

-- ---- Profile shifts of Driven Gear (can be different from Driving Gear) ----
local x_coef_bottom_driven  = param("real", "Profile Shift Coefficient Bottom-Driven Gear", x_max, x_min, x_max)
local x_coef_top_driven     = param("real", "Profile Shift Coefficient Top-Driven Gear", x_min, x_min, x_max)

-- ---- Tooth geometry coefficients ----
local rho_coef      = param("real", "Fillet Coefficient", 0.38, 0.05, 0.8)  -- coefficient of tip radius of generating rack

-- ---- Shaft and assembly ----
local shaft_dia     = param("real", "Shaft diameter (mm)", 17.0, 10.0, 25.0) -- Shaft diameter [mm]
local gear_rotation = param("real", "Driving Gear Rotation (Anti-Clockwise direction) (deg)", 0, 0, 90.0)
local clearance     = param("real", "Clearance (mm)", 0.0, 0.0, 5.0)          -- extra centre distance [mm]

-- ---- Main control: axial adjustment of the driven gear ----
local axial_offset  = ui_scalar("Axial offset(mm)", 0, 0, b - mesh_min_overlap)

-- ---- Backlash demonstration ----
local show_intersection = ui_bool("Show Intersection Body", false) -- Highlight overlapping volume (backlash probe)
-- Rotates ONLY the driven gear so backlash can be probed
local driven_gear_angular_offset = 0
if advanced or show_intersection then
  driven_gear_angular_offset = ui_scalar("Driven Gear angular offset (deg)", 0, -2.0, 2.0)
end

-- ---- Visualization toggles ----
local show_driving_gear = ui_bool("Show Driving Gear", true)
local show_driven_gear  = ui_bool("Show Driven Gear", true)
local show_shafts       = ui_bool("Show Shafts", true)
local show_shim         = ui_bool("Show Shim", true)
local show_cap          = ui_bool("Show Caps", true)
local show_handle       = ui_bool("Show Handle", true)
local show_wooden_plate = ui_bool("Show Wooden Plate", true)

-- ============================================================
-- SECTION 3: HELPER FUNCTIONS
-- ============================================================

-- Messages collected during the build and printed at the end
local messages = {}
local function note(fmt, ...)
  messages[#messages + 1] = string.format(fmt, ...)
end

-- Floating-point modulo  (always non-negative for positive b)
local function mod(a, b)
  return a - math.floor(a / b) * b
end

-- Cotangent
local function cot(x)
  return math.cos(x) / math.sin(x)
end

-- Involute function and its inverse (Newton iteration)
local function inv(a)
  return math.tan(a) - a
end

local function inv_inverse(y)
  local a = (3 * y) ^ (1 / 3) -- good start value for small angles
  for _ = 1, 30 do
    local t = math.tan(a)
    a = a - (t - a - y) / (t * t)
  end
  return a
end

-- sin / cos in degrees
local function sind(a) return math.sin(math.rad(a)) end
local function cosd(a) return math.cos(math.rad(a)) end

-- Linearly spaced vector of n values from a to b (inclusive)
local function linspace(a, b, n)
  local t = {}
  if n <= 1 then
    t[1] = a
    return t
  end
  for i = 1, n do
    t[i] = a + (b - a) * (i - 1) / (n - 1)
  end
  return t
end

-- Append arrays: source[i1..i2] to the end of destination
local function append_range(dst, src, i1, i2)
  for i = i1, i2 do
    dst[#dst + 1] = src[i]
  end
end

-- Append arrays: source[i1..i2] (reversed) to the end of destination
local function append_reverse_range(dst, src, i1, i2)
  for i = i2, i1, -1 do
    dst[#dst + 1] = src[i]
  end
end

-- Convert parallel x/y arrays from Cartesian to polar  (theta, r)
local function cart2pol(x, y)
  local theta, r = {}, {}
  for i = 1, #x do
    theta[i] = math.atan2(y[i], x[i])
    r[i]     = math.sqrt(x[i] * x[i] + y[i] * y[i])
  end
  return theta, r
end

-- ============================================================
-- SECTION 4: BEVELOID GEAR
-- ============================================================

local h_a = h_a_coef * m -- addendum height of the generating rack [mm]
local rho = rho_coef * m -- tip radius of generating rack [mm]

local num_layers   = res -- number of cross-section layers along the face width
local res_fillet   = res -- sample points along each fillet arc
local res_involute = res -- sample points along each involute curve
local res_arcs     = res -- sample points for top-land and bottom-land arcs

-- Tooth counts actually used everywhere (centre distance, phase, ratio and geometry)
if z_driving < zmin or z_driven < zmin then
  note("NOTE: tooth count raised to the undercut limit zmin = %d at %d deg pressure angle", zmin, alpha_n_deg)
end
z_driving = math.max(math.floor(z_driving + 0.5), zmin)
z_driven  = math.max(math.floor(z_driven + 0.5), zmin)

-- Cone angle from the profile-shift gradient: tan(delta) = m (x_top - x_bottom) / b
local function cone_angle(x_bottom, x_top)
  return math.atan((m * (x_top - x_bottom)) / b)
end

-- Transverse pressure angle of a beveloid with cone angle delta
local function transverse_pressure_angle(delta)
  return math.atan(math.tan(alpha_n_rad) * math.cos(delta))
end

-- Addendum (tip) circle radius
local function tip_radius(z_local, x_local)
  return z_local * m / 2 + m * (1 + x_local)
end

-- Root circle radius
local function root_radius(z_local, x_local, delta)
  return z_local * m / 2 + x_local * m - h_a / math.cos(delta)
end

-- Builds a single beveloid gear solid as an IceSL polyhedron, spanning z = 0 .. b.
-- Parameters:
--   z_local   : number of teeth (already checked against zmin)
--   x_bottom  : profile shift coefficient at z = 0 (bottom face)
--   x_top     : profile shift coefficient at z = b (top face)
--   label     : name used in console messages
local function make_beveloid(z_local, x_bottom, x_top, label)
  local delta       = cone_angle(x_bottom, x_top)       -- beveloid cone angle
  local alpha_t     = transverse_pressure_angle(delta)  -- transverse pressure angle (same for every slice)
  local r_p         = z_local * m / 2.0                 -- pitch radius
  local r_b         = r_p * math.cos(alpha_t)           -- base circle radius
  local pitch_angle = 2.0 * math.pi / z_local           -- angular pitch between teeth
  local undercut_layers = 0

  -- ----------------------------------------------------------
  -- Inner function: 2-D tooth contour at one axial cross-section
  -- x_local is the profile shift coefficient at this slice
  -- Returns two arrays (contour_x, contour_y) for all z_local teeth
  -- ----------------------------------------------------------
  local function build_layer_contour(x_local)
    local s_t = m * (math.pi / 2.0 + 2.0 * x_local * math.tan(alpha_t)) -- tooth thickness on pitch circle
    local x_n = x_local * math.cos(delta)                               -- normal-plane profile shift
    local r_f = r_p + x_local * m - h_a / math.cos(delta)               -- root circle radius
    local r_a = r_p + m * (1.0 + x_local)                               -- addendum circle radius

    -- ---- Undercut check ----
    local lhs      = r_b * math.tan(alpha_t)
    local rhs      = (h_a - x_n * m - rho * (1.0 - sin_alpha_n)) /
        (math.sin(alpha_t) * math.cos(delta))
    local undercut = lhs < rhs -- true => undercut condition detected

    -- Fillet/involute junction point (polar coords: r_IF, psi_IF)
    local r_IF   -- radius at which the involute and fillet meet
    local psi_IF -- angle at which the involute and fillet meet
    if not undercut then
      local term = lhs - rhs
      r_IF       = math.sqrt(r_b * r_b + term * term)
      psi_IF     = alpha_t
    else
      -- Fallback parameters for undercut: junction approximated at the base circle
      r_IF   = r_b
      psi_IF = alpha_t
      undercut_layers = undercut_layers + 1
    end

    -- ==========================================
    -- Fillet Profile
    -- ==========================================

    -- Right-flank fillet
    local filletR_x, filletR_y = {}, {}
    local psi_vals = linspace(psi_IF, math.pi / 2.0, res_fillet)
    for i = 1, #psi_vals do
      local psi   = psi_vals[i]
      local psi_n = math.atan(math.tan(psi) / math.cos(delta))
      local A     = (h_a - x_n * m - rho * (1.0 - math.sin(psi_n))) /
          math.cos(delta)   -- shorthand for common term in brackets
      local phi_f = (       -- angular position of the rack contact point on the pitch circle
        A * cot(psi) +
        (math.pi * m / 4.0) +
        h_a * math.tan(alpha_n_rad) +
        rho * (((1.0 - sin_alpha_n) / math.cos(alpha_n_rad)) - math.cos(psi_n))
      ) / r_p

      local xi_F  = r_p * math.sin(phi_f) -
          (A / math.sin(psi)) * math.cos(psi - phi_f) -- abscissa of fillet point
      local eta_F = r_p * math.cos(phi_f) -
          (A / math.sin(psi)) * math.sin(psi - phi_f) -- ordinate of fillet point

      filletR_x[#filletR_x + 1] = xi_F
      filletR_y[#filletR_y + 1] = eta_F
    end

    -- Left-flank fillet: mirror of right fillet across tooth centre-line
    local filletL_x, filletL_y = {}, {}
    for i = #filletR_x, 1, -1 do
      filletL_x[#filletL_x + 1] = -filletR_x[i]
      filletL_y[#filletL_y + 1] = filletR_y[i]
    end

    -- ==========================================
    -- Involute Profile
    -- ==========================================

    local phi_r_b  = s_t / (2.0 * r_p) + math.tan(alpha_t)                  -- roll angle at pitch point
    local phi_r_a  = phi_r_b - math.sqrt((r_a * r_a) / (r_b * r_b) - 1.0)   -- roll angle at tip circle
    local phi_r_IF = phi_r_b - math.sqrt((r_IF * r_IF) / (r_b * r_b) - 1.0) -- roll angle at fillet/involute junction

    -- Right-flank involute: from tip (phi_r_a) down to junction (phi_r_IF)
    local invR_x, invR_y = {}, {}
    local phi_vals = linspace(phi_r_a, phi_r_IF, res_involute)
    for i = 1, #phi_vals do
      local phi_i = phi_vals[i]
      local xi_I  = r_p * math.sin(phi_i) -
          ((r_p * phi_i - s_t / 2.0) * math.cos(alpha_t)) *
          math.cos(phi_i - alpha_t) -- abscissa of involute point
      local eta_I = r_p * math.cos(phi_i) +
          ((r_p * phi_i - s_t / 2.0) * math.cos(alpha_t)) *
          math.sin(phi_i - alpha_t) -- ordinate of involute point

      invR_x[#invR_x + 1] = xi_I
      invR_y[#invR_y + 1] = eta_I
    end

    -- Left-flank involute: mirror of right
    local invL_x, invL_y = {}, {}
    for i = #invR_x, 1, -1 do
      invL_x[#invL_x + 1] = -invR_x[i]
      invL_y[#invL_y + 1] = invR_y[i]
    end

    -- ==========================================
    -- Top-Land Arc
    -- ==========================================
    local phi_top_land_start = math.atan2(invR_y[1], invR_x[1])             -- starting angle of top-land arc
    local phi_top_land_end   = math.atan2(invL_y[#invL_y], invL_x[#invL_x]) -- ending angle of top-land arc
    while phi_top_land_end < phi_top_land_start do
      phi_top_land_end = phi_top_land_end + 2.0 * math.pi
    end

    local x_top_land_arc = {}                                                     -- abscissa of top-land arc points
    local y_top_land_arc = {}                                                     -- ordinate of top-land arc points
    local phi_top_land = linspace(phi_top_land_start, phi_top_land_end, res_arcs) -- angles for sampling the top-land arc
    for i = 1, #phi_top_land do
      x_top_land_arc[#x_top_land_arc + 1] = r_a * math.cos(phi_top_land[i])
      y_top_land_arc[#y_top_land_arc + 1] = r_a * math.sin(phi_top_land[i])
    end

    -- ==========================================
    -- Bottom-Land Arc
    -- ==========================================
    local phi_bottom_land_L    = math.atan2(filletL_y[1], filletL_x[1])                   -- starting angle of bottom-land arc
    local phi_bottom_land_R    = math.atan2(filletR_y[#filletR_y], filletR_x[#filletR_x]) -- ending angle of bottom-land arc
    local phi_root_land_R_next = phi_bottom_land_R + pitch_angle                          -- right flank of the next tooth
    local d_phi_bottom         = mod(phi_root_land_R_next - phi_bottom_land_L, 2.0 * math.pi) -- span, wrapped to [0, 2pi]

    local x_bottom_arc    = {}                                                                 -- abscissa of bottom-land arc points
    local y_bottom_arc    = {}                                                                 -- ordinate of bottom-land arc points
    local phi_bottom_land = linspace(phi_bottom_land_L, phi_bottom_land_L + d_phi_bottom, res_arcs) -- sampling angles
    for i = 1, #phi_bottom_land do
      x_bottom_arc[#x_bottom_arc + 1] = r_f * math.cos(phi_bottom_land[i])
      y_bottom_arc[#y_bottom_arc + 1] = r_f * math.sin(phi_bottom_land[i])
    end

    -- ==========================================
    -- Single Tooth-Pitch Contour
    -- Ordering: right-fillet -> right-involute -> top-land -> left-involute -> left-fillet -> bottom-land
    -- ==========================================
    local x_pitch, y_pitch = {}, {}

    append_reverse_range(x_pitch, filletR_x, 1, #filletR_x)
    append_reverse_range(y_pitch, filletR_y, 1, #filletR_y)

    append_reverse_range(x_pitch, invR_x, 2, #invR_x)
    append_reverse_range(y_pitch, invR_y, 2, #invR_y)

    append_range(x_pitch, x_top_land_arc, 2, #x_top_land_arc)
    append_range(y_pitch, y_top_land_arc, 2, #y_top_land_arc)

    append_reverse_range(x_pitch, invL_x, 2, #invL_x)
    append_reverse_range(y_pitch, invL_y, 2, #invL_y)

    append_reverse_range(x_pitch, filletL_x, 2, #filletL_x)
    append_reverse_range(y_pitch, filletL_y, 2, #filletL_y)

    append_range(x_pitch, x_bottom_arc, 2, #x_bottom_arc)
    append_range(y_pitch, y_bottom_arc, 2, #y_bottom_arc)

    -- ==========================================
    -- Replicate tooth profiles around the pitch circle to build the full layer contour
    -- ==========================================
    local theta_pitch, r_pitch = cart2pol(x_pitch, y_pitch)
    local contour_x = {} -- abscissa of the full layer contour (all teeth)
    local contour_y = {} -- ordinate of the full layer contour (all teeth)

    for tooth = 0, z_local - 1 do
      local phi = tooth * pitch_angle
      for k = 1, #theta_pitch - 1 do
        contour_x[#contour_x + 1] = r_pitch[k] * math.cos(theta_pitch[k] + phi)
        contour_y[#contour_y + 1] = r_pitch[k] * math.sin(theta_pitch[k] + phi)
      end
    end

    return contour_x, contour_y
  end -- end build_layer_contour

  -- ==========================================
  -- 3-D Polyhedron Construction
  -- ==========================================

  local points        = {}
  local faces         = {}

  local shift_values  = linspace(x_bottom, x_top, num_layers) -- profile shift at each layer
  local z_coords      = linspace(0.0, b, num_layers)          -- Z position of each layer

  local pts_per_layer = 0

  -- ---- Vertex generation: one contour per layer ----
  for l = 1, num_layers do
    local cx, cy      = build_layer_contour(shift_values[l])
    pts_per_layer     = #cx
    local z_val_layer = z_coords[l]
    for i = 1, pts_per_layer do
      points[#points + 1] = v(cx[i], cy[i], z_val_layer)
    end
  end

  -- ---- Side face generation ----
  for l = 1, num_layers - 1 do
    local lower_start = (l - 1) * pts_per_layer
    local upper_start = l * pts_per_layer
    for i = 0, pts_per_layer - 1 do
      local current_lower = lower_start + i
      local next_lower    = lower_start + ((i + 1) % pts_per_layer)
      local current_upper = upper_start + i
      local next_upper    = upper_start + ((i + 1) % pts_per_layer)
      faces[#faces + 1]   = v(current_lower, next_lower, current_upper)
      faces[#faces + 1]   = v(next_lower, next_upper, current_upper)
    end
  end

  -- ---- Bottom cap generation ----
  local bottom_center_idx = #points
  points[#points + 1] = v(0, 0, z_coords[1])
  for i = 0, pts_per_layer - 1 do
    local current = i
    local next_pt = (i + 1) % pts_per_layer
    faces[#faces + 1] = v(bottom_center_idx, next_pt, current)
  end

  -- ---- Top cap generation ----
  local top_center_idx  = #points
  points[#points + 1]   = v(0, 0, z_coords[num_layers])
  local top_layer_start = (num_layers - 1) * pts_per_layer
  for i = 0, pts_per_layer - 1 do
    local current = top_layer_start + i
    local next_pt = top_layer_start + ((i + 1) % pts_per_layer)
    faces[#faces + 1] = v(top_center_idx, current, next_pt)
  end

  if undercut_layers > 0 then
    -- zmin uses the normal pressure angle; the smaller transverse angle of a beveloid can
    -- still give a slight undercut at the thin (negative-shift) end
    note("NOTE: %s gear: slight undercut in %d of %d layers near the thin end (fillet junction approximated at the base circle)",
      label, undercut_layers, num_layers)
  end

  local gear_solid = polyhedron(points, faces)
  return gear_solid
end -- end make_beveloid

-- ============================================================
-- SECTION 5: HARDWARE
-- ============================================================

-- ---- Screw (used to cut countersunk holes into the mount) ----
local screwHead_height   = screwHead_dia / 2
local total_screw_length = screwHead_height + screw_thread_height

local function make_screw()
  local hole_radius = screwHole_dia / 2
  local screwHead   = cone(hole_radius, screwHead_dia / 2, screwHead_height)
  local screwThread = cylinder(hole_radius, screw_thread_height)
  local screw = union(translate(0, 0, screw_thread_height) * screwHead,
                      screwThread)
  return screw
end

-- ---- Mount: square block with four countersunk screw holes ----
local function make_mount(mount_length)
  local mount  = cube(mount_length, mount_length, mount_height)
  local screw1 = translate(mount_length / 2.5, mount_length / 2.5, mount_height - total_screw_length) * make_screw()
  local screw2 = translate(-mount_length / 2.5, mount_length / 2.5, mount_height - total_screw_length) * make_screw()
  local screw3 = translate(-mount_length / 2.5, -mount_length / 2.5, mount_height - total_screw_length) * make_screw()
  local screw4 = translate(mount_length / 2.5, -mount_length / 2.5, mount_height - total_screw_length) * make_screw()

  local screws = union({ screw1, screw2, screw3, screw4 })
  mount = difference(mount, screws)
  return mount
end

-- ---- Threads: a stack of off-centre circles that rotate with height ----
local function circle_offset(r, o)
  local tbl = {}
  local n = 128
  for i = 1, n do
    local a = 360 * i / n
    tbl[i] = r * v(cosd(a), sind(a), 0) + o
  end
  return tbl
end

-- ra: circle radius, rs: radial offset (thread depth ~ 2*rs), len: thread length
local function make_thread(ra, rs, len)
  if not show_threads then
    return cylinder(ra + rs, len) -- fast stand-in with the same outer diameter
  end
  local all_tbl = {}
  local n = math.max(2, math.floor(len * thread_steps_per_mm + 0.5))
  for h = 1, n do
    local a = h * thread_deg_per_step
    all_tbl[h] = circle_offset(ra, v(rs * cosd(a), rs * sind(a), h / thread_steps_per_mm))
  end
  return sections_extrude(all_tbl)
end

-- ---- Shaft on its mount, optionally threaded at the top ----
local function make_shaft(shaft_diameter, shaft_total_length, thread_length, mount)
  local shaft_cylinder_length = shaft_total_length - thread_length + spring_compressed_h
  local shaft_cylinder = cylinder((shaft_diameter / 2) - shaft_tolerance, shaft_cylinder_length)
  local shaft
  if thread_length > 0 then
    local shaft_thread = make_thread((shaft_diameter / 2) - thread_offset - thread_tolerance, thread_offset, thread_length)
    shaft = union({ translate(0, 0, -mount_height) * mount,
                    translate(0, 0, shaft_cylinder_length - 0.2) * shaft_thread,
                    shaft_cylinder })
  else
    shaft = union({ translate(0, 0, -mount_height) * mount,
                    shaft_cylinder })
  end
  return shaft
end

-- ---- Hexagonal prism, width across flats = face_width ----
local function make_hexagon(face_width, height)
  local head = intersection {
    cube(face_width, 1.5 * face_width, height),
    rotate(0, 0, 60) * cube(face_width, 1.5 * face_width, height),
    rotate(0, 0, 120) * cube(face_width, 1.5 * face_width, height),
  }
  return head
end

-- ---- Threaded cap nut with closed top ----
local function make_cap_nut(thread_height)
  local shaft_thread = translate(0, 0, -thread_height / 4)
      * make_thread((shaft_dia / 2) - thread_offset, thread_offset, 1.5 * thread_height)
  local hexagon = make_hexagon((1.3 * shaft_dia), thread_height)
  local nut = difference(hexagon, shaft_thread)
  nut = translate(0, 0, -thread_height / 4) * nut

  local nut_top_height = 3
  local nut_top = make_hexagon((1.3 * shaft_dia), nut_top_height)
  nut = union(nut, translate(0, 0, 3 * thread_height / 4) * nut_top)
  return nut
end

-- ============================================================
-- Snap pin and pin hole (adapted from IceSL's pins.lua asset, see header)
-- ============================================================

local function pin_solid(h, r, lh, lt)
  return union({
    cylinder(r, h - lh),
    -- lip
    translate(0, 0, h - lh) * cone(r, r + (lt / 2), lh * 0.25),
    translate(0, 0, h - lh + lh * 0.25) * cylinder(r + (lt / 2), lh * 0.25),
    translate(0, 0, h - lh + lh * 0.50) * cone(r + (lt / 2), r - (lt / 2), lh * 0.50),
  })
end

local function pinhole_impl(h, r, lh, lt, t, tight)
  -- h = shaft height
  -- r = shaft radius
  -- lh = lip height
  -- lt = lip thickness
  -- t = tolerance
  -- tight = set to false if you want a joint that spins easily
  local c = cylinder(r, h + 0.2)
  if tight == false then
    c = union(c, cylinder(r + (t / 2) + 0.25, h + 0.2))
  end

  return union({
    pin_solid(h, r + (t / 2), lh, lt),
    c,
    -- widen the entrance hole to make insertion easier
    translate(0, 0, -0.1) * cone(r + (t / 2) + (lt / 2), r, lh / 3),
  })
end

local function pinhole(args)
  local tight = args.tight
  if tight == nil then tight = true end -- (the original "args.tight or true" ignored tight = false)
  return pinhole_impl(
    args.h or 10,
    args.r or 4,
    args.lh or 3,
    args.lt or 1,
    args.t or 0.3,
    tight)
end

local function pin_vertical(h, r, lh, lt)
  -- h = shaft height
  -- r = shaft radius
  -- lh = lip height
  -- lt = lip thickness
  return difference({
    pin_solid(h, r, lh, lt),
    -- center cut
    translate(-r * 0.5 / 2, -(r * 2 + lt * 2) / 2, h / 2) * scale(r * 0.5, r * 2 + lt * 2, h) * translate(0.5, 0.5, 0.5) * box(1),
    translate(0, 0, h / 4) * cylinder(r / 2.5, h + lh),
    -- center curve
    translate(0, 0, h / 2) * rotate(90, 0, 0) * translate(Z * -r) * cylinder(r * 0.5 / 2, r * 2),
    -- side cuts
    translate(-r * 2, r * .85, -1) * scale(r * 4, r * 2, h + 2) * translate(0.5, 0.5, 0.5) * box(1),
    mirror(v(0, 1, 0)) * translate(-r * 2, r * .85, -1) * scale(r * 4, r * 2, h + 2) * translate(0.5, 0.5, 0.5) * box(1),
  })
end

local function pin_horizontal(h, r, lh, lt)
  return translate(0, h / 2, r * 1.125 - lt) * rotate(90, 0, 0) * pin_vertical(h, r, lh, lt)
end

local function pin_impl(h, r, lh, lt, side)
  -- side = set to true if you want it printed horizontally
  if side then
    return pin_horizontal(h, r, lh, lt)
  else
    return pin_vertical(h, r, lh, lt)
  end
end

local function pin(args)
  return pin_impl(
    args.h or 10,
    args.r or 4,
    args.lh or 3,
    args.lt or 1,
    args.side or false)
end

-- ============================================================
-- Handle: hexagon grip on a snap pin (pin points +Z, grip below z = 0)
-- ============================================================

local handle_pin     = pin { h = handle_pin_height }
local handle_hexagon = make_hexagon(handle_hexagon_w, handle_hexagon_h)
local handle = union({
  handle_pin,
  translate(0, 0, -handle_hexagon_h) * handle_hexagon,
})

-- ============================================================
-- SECTION 6: CENTRE DISTANCE AND BACKLASH PREDICTION
-- ============================================================

local delta_driving = cone_angle(x_coef_bottom_driving, x_coef_top_driving)
local delta_driven  = cone_angle(x_coef_bottom_driven, x_coef_top_driven)
if math.abs(delta_driving - delta_driven) > 1e-9 then
  note("NOTE: the gears have different cone angles, so backlash will vary across the face width")
end
local alpha_t = transverse_pressure_angle(delta_driving)

-- ---- Operating center distance ----
local r_p_driving              = (z_driving * m) / 2      -- pitch radius of the driving gear
local r_p_driven               = (z_driven * m) / 2       -- pitch radius of the driven gear
local standard_center_distance = r_p_driving + r_p_driven -- center distance without profile shift or clearance

-- Use the mid-face profile shift of each gear (design point: faces fully aligned, zero backlash)
local driving_x_mid            = (x_coef_bottom_driving + x_coef_top_driving) / 2.0 -- mid-face profile shift of driving gear
local driven_x_mid             = (x_coef_bottom_driven + x_coef_top_driven) / 2.0   -- mid-face profile shift of driven gear
local sum_x                    = driving_x_mid + driven_x_mid                       -- total mid-face profile shift

-- Exact involute relation: inv(alpha_w) = inv(alpha_t) + 2 tan(alpha_t) (x1 + x2) / (z1 + z2)
local inv_alpha_w = inv(alpha_t) + 2 * math.tan(alpha_t) * sum_x / (z_driving + z_driven)
local operating_center_dist
if inv_alpha_w > 0 then
  operating_center_dist = standard_center_distance * math.cos(alpha_t) / math.cos(inv_inverse(inv_alpha_w)) + clearance
else
  operating_center_dist = standard_center_distance + sum_x * m + clearance -- linear approximation as a fallback
  note("NOTE: profile shift sum too negative for the exact formula; using a0 + (x1 + x2) m")
end

-- ---- Axial placement (world z) ----
local driving_z0 = spring_compressed_h                                     -- bottom face of the driving gear
local gear_top   = driving_z0 + b                                          -- top face of the driving gear
local driven_top = spring_compressed_h + 2 * b - axial_offset - mesh_min_overlap -- top face of the (flipped) driven gear
local driven_z0  = driven_top - b
local overlap_lo = math.max(driving_z0, driven_z0)
local overlap_hi = math.min(gear_top, driven_top)
local z_mesh     = (overlap_lo + overlap_hi) / 2                           -- any plane in the overlap gives the same sum

-- Local profile shifts at the mesh plane (the driven gear is flipped, so its "bottom" is at driven_top)
local x_driving_mesh = x_coef_bottom_driving + (x_coef_top_driving - x_coef_bottom_driving) * (z_mesh - driving_z0) / b
local x_driven_mesh  = x_coef_bottom_driven + (x_coef_top_driven - x_coef_bottom_driven) * (driven_top - z_mesh) / b

-- Circumferential backlash on the operating pitch circle for shifts x1, x2 at centre distance a
local function predicted_backlash(x1, x2, a)
  local cos_aw = standard_center_distance * math.cos(alpha_t) / a
  if cos_aw >= 1 then return nil end
  local aw       = math.acos(cos_aw)
  local d1, d2   = z_driving * m, z_driven * m
  local dw1, dw2 = d1 * math.cos(alpha_t) / cos_aw, d2 * math.cos(alpha_t) / cos_aw
  local s1 = m * (math.pi / 2 + 2 * x1 * math.tan(alpha_t))
  local s2 = m * (math.pi / 2 + 2 * x2 * math.tan(alpha_t))
  local sw1 = dw1 * (s1 / d1 + inv(alpha_t) - inv(aw))
  local sw2 = dw2 * (s2 / d2 + inv(alpha_t) - inv(aw))
  return math.pi * dw1 / z_driving - sw1 - sw2, dw2 / 2, aw
end

local backlash, r_w_driven, alpha_w = predicted_backlash(x_driving_mesh, x_driven_mesh, operating_center_dist)

-- Tip/root clearance at the mesh plane (negative = tip of one gear hits the root of the other)
local tip_clearance = math.min(
  operating_center_dist - tip_radius(z_driving, x_driving_mesh) - root_radius(z_driven, x_driven_mesh, delta_driven),
  operating_center_dist - tip_radius(z_driven, x_driven_mesh) - root_radius(z_driving, x_driving_mesh, delta_driving))
if tip_clearance < 0 then
  note("WARNING: tip/root interference (%.2f mm) - increase 'Clearance (mm)'", tip_clearance)
end

-- ============================================================
-- SECTION 7: ASSEMBLY AND OUTPUT
-- ============================================================

-- ---- Angular phase and gear ratio ----
local phase_offset = 180 / z_driven -- half-tooth offset so flanks mesh (not tip-to-tip)
local gear_ratio   = z_driving / z_driven

-- ---- Sizes derived from the gear geometry ----
local r_root_min = root_radius(z_driving, math.min(x_coef_bottom_driving, x_coef_top_driving), delta_driving)
local driving_shaft_extra_radius = math.min(2 * shaft_dia, r_root_min - hub_margin) -- hub under the driving gear
local driving_shaft_extra_height = spring_compressed_h + b / 4
local handle_offset = r_root_min - handle_margin                                   -- radial position of the handle
local mount_length  = operating_center_dist - mount_gap

if shaft_dia / 2 >= r_root_min - hub_margin then
  note("WARNING: shaft bore (%.1f mm) cuts into the tooth root (%.1f mm) - reduce shaft diameter", shaft_dia / 2, r_root_min)
end
if handle_offset - handle_hexagon_w / 2 < shaft_dia / 2 then
  note("WARNING: handle hole overlaps the shaft bore - increase module/teeth or reduce shaft diameter")
end
if pinhole_depth + 0.2 > b - (driving_shaft_extra_height - driving_z0) then
  note("WARNING: face width too small - the handle hole breaks into the hub recess")
end
if mount_length < 2 * shaft_dia then
  note("WARNING: mounting blocks are very small (%.1f mm)", mount_length)
end

-- ---- Build raw gear bodies (local frame, z = 0 .. b) ----
local driving_gear = make_beveloid(z_driving, x_coef_bottom_driving, x_coef_top_driving, "Driving")
local driven_gear  = make_beveloid(z_driven, x_coef_bottom_driven, x_coef_top_driven, "Driven")

-- ---- Hole for handle (snap-pin hole entering from the top face of the driving gear) ----
local handle_hole_diff = rotate(0, 180, 0) * translate(-handle_offset, 0, -b)
    * pinhole { h = pinhole_depth, t = tolerance, tight = false }
driving_gear = difference(driving_gear, handle_hole_diff)

-- ---- Subtract shaft bores from each gear ----
driving_gear = difference(driving_gear, cylinder(shaft_dia / 2, b))
driven_gear  = difference(driven_gear, cylinder(shaft_dia / 2, b))

-- ---- Assembly transforms ----

-- Driving gear: rotate -90 deg so a tooth tip aligns with +X (towards the driven gear), lifted by the spring
local driving_rotation    = rotate(gear_rotation - 90, v(0, 0, 1))
local meshed_driving_gear = translate(0, 0, driving_z0) * driving_rotation * driving_gear
-- Cutting for support (recess for the driving shaft extra)
meshed_driving_gear = difference(meshed_driving_gear, cylinder(driving_shaft_extra_radius, driving_shaft_extra_height))

-- Driven gear: flipped about Y so the tapers face each other; phase offset + synced ratio
-- rotation + backlash probe offset; moved down by the axial offset
local meshed_driven_gear = translate(operating_center_dist, 0, driven_top)
    * rotate(180, v(0, 1, 0))
    * rotate(phase_offset + (gear_rotation * gear_ratio) - driven_gear_angular_offset - 90, v(0, 0, 1))
    * driven_gear

-- Handle: flipped so the pin points down into the hole and seated on the gear top.
-- It uses the same rotation as the gear, so it follows "Driving Gear Rotation".
local meshed_handle = driving_rotation
    * translate(handle_offset, 0, gear_top + (handle_pin_height - pinhole_depth))
    * rotate(0, 180, 0)
    * handle

-- ============================================================
-- SHAFTS
-- ============================================================

local mount = make_mount(mount_length)

local driving_shaft       = make_shaft(shaft_dia, b + driving_shaft_protrusion, driving_thread_length, mount)
local driving_shaft_extra = cylinder(driving_shaft_extra_radius - driving_shaft_tolerance, driving_shaft_extra_height)
driving_shaft = union(driving_shaft, driving_shaft_extra)

local driven_thread_length    = b + shim_thickness
local driven_nonThread_length = b + shim_thickness
local driven_shaft = translate(operating_center_dist, 0, 0)
    * make_shaft(shaft_dia, driven_nonThread_length + driven_thread_length, driven_thread_length, mount)
-- driven shaft indent (keyway so the shims cannot turn)
driven_shaft = difference(driven_shaft, translate(operating_center_dist + shaft_dia / 2, 0, 0) * cube(key_width, key_width, 3 * b))

-- ============================================================
-- SHIM (above and below the driven gear, keyed to the shaft)
-- ============================================================

local shim_z = spring_compressed_h + 2 * b - mesh_min_overlap -- upper shim seat at zero axial offset
local shim = translate(operating_center_dist, 0, shim_z)
    * difference(cylinder(shaft_dia, shim_thickness), cylinder(shim_tolerance + shaft_dia / 2, shim_thickness))
local shim_slotted = union(shim, translate(operating_center_dist + shaft_dia / 2, 0, shim_z)
    * cube(key_width - shim_tolerance, key_width - shim_tolerance, shim_thickness))

-- ============================================================
-- CAPS
-- ============================================================

local driving_cap_cylinder      = cylinder(3 * shaft_dia / 4, driving_cap_cylinder_height)
local driving_cap_cylinder_hole = cylinder(shaft_dia / 2, driving_cap_cylinder_height + 2)
driving_cap_cylinder = translate(0, 0, -1.25) * difference(driving_cap_cylinder, driving_cap_cylinder_hole)
local driving_cap_nut = make_cap_nut(driving_cap_nut_height)
local driving_cap = translate(0, 0, gear_top + driving_cap_lift) * union(driving_cap_cylinder, driving_cap_nut)

-- The driven cap screws down with the shims: it turns thread_deg_per_mm per mm of travel
local driven_cap_height = b + shim_thickness
local driven_cap_z = shim_z + shim_thickness - axial_offset + driven_cap_height / 4 + cap_gap
local driven_cap = translate(operating_center_dist, 0, driven_cap_z)
    * rotate(0, 0, -thread_deg_per_mm * axial_offset)
    * make_cap_nut(driven_cap_height)

-- ============================================================
-- WOODEN PLATE
-- ============================================================

local wooden_plate = translate(operating_center_dist / 2, 0, -mount_height - wood_height)
    * cube(wood_length, wood_breadth, wood_height)

-- Tip radius of driving gear / driven gear (largest profile shift)
local ra1 = tip_radius(z_driving, math.max(x_coef_bottom_driving, x_coef_top_driving))
local ra2 = tip_radius(z_driven, math.max(x_coef_bottom_driven, x_coef_top_driven))
local half_extent = math.max(ra1, ra2, mount_length / 2)
if operating_center_dist + 2 * half_extent > wood_length or 2 * half_extent > wood_breadth then
  note("NOTE: the assembly is larger than the %.0f x %.0f mm wooden plate", wood_length, wood_breadth)
end

-- ============================================================
-- INTERSECTION BODY AND OUTPUT
-- ============================================================

-- Empty                -> flanks not touching
-- Slight intersection  -> flanks just touching
-- Volume               -> flanks penetrating

if show_intersection then
  local intersection_body = intersection(meshed_driving_gear, meshed_driven_gear)
  local bb = bbox(intersection_body)
  if bb:empty() then
    note("Backlash probe: no intersection - flanks not touching (positive backlash)")
  else
    emit(intersection_body, brush.intersection)
    note("Backlash probe: intersection found - flanks touching or penetrating")
  end
else
  if show_driving_gear then emit(meshed_driving_gear, brush.driving_gear) end
  if show_driven_gear then emit(meshed_driven_gear, brush.driven_gear) end
  if show_shafts then
    emit(driving_shaft, brush.shaft)
    emit(driven_shaft, brush.shaft)
  end
  if show_shim then
    emit(translate(0, 0, -axial_offset) * shim_slotted, brush.shim)
    emit(translate(0, 0, -axial_offset - b - shim_thickness) * shim_slotted, brush.shim)
  end
  if show_cap then
    emit(driving_cap, brush.driving_cap)
    emit(driven_cap, brush.driven_cap)
  end
  if show_handle then
    emit(meshed_handle, brush.handle)
  end
  if show_wooden_plate then emit(wooden_plate, brush.wooden_plate) end
end

-- ---- Console report ----
print("==== Beveloid gear pair ====")
print(string.format("Teeth %d / %d, module %.2f mm, normal pressure angle %.1f deg",
  z_driving, z_driven, m, alpha_n_deg))
print(string.format("Cone angle %.2f deg, transverse pressure angle %.2f deg",
  math.deg(delta_driving), math.deg(alpha_t)))
print(string.format("Centre distance %.3f mm (design sum of mid-face shifts %.3f)",
  operating_center_dist, sum_x))
print(string.format("Axial offset %.2f mm -> engaged width %.2f mm, local shift sum %.3f",
  axial_offset, overlap_hi - overlap_lo, x_driving_mesh + x_driven_mesh))
if backlash then
  print(string.format("Predicted backlash %.3f mm circumferential (%.3f mm normal), driven-gear free play %.3f deg",
    backlash, backlash * math.cos(alpha_w), math.deg(backlash / r_w_driven)))
end
for _, msg in ipairs(messages) do
  print(msg)
end