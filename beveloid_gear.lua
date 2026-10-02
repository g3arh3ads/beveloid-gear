-- ============================================================
-- Team 37: Conical Involute Gears(Beveloidverzahnungen) for backlash reduction by axial gear adjustment.
-- ============================================================

-- The following script is a demonstration of straight conical involute gear design and meshing,
-- based on the analytical rack-generation method described by Brauer (2002).

-- Citation:
-- Brauer, Jesper. (2002). Analytical geometry of straight conical involute gears. Mechanism and Machine Theory. 37, 127-141.
-- doi: 10.1016/S0094-114X(01)00062-3.

-- ============================================================
-- SECTION 0: Instructions and Overview
-- ============================================================

-- This script builds a pair of meshing conical involute gears with user-defined geometry and profile shifts.
-- The UI sliders allow to explore how different profile shift distributions across the face width affect the gear geometry and meshing behaviour.

-- To allow users with less computational resources to explore the design space, all curve sampling resolutions are tied to a single "Resolution" slider.
-- But using less resolution will make the gear profiles more faceted and less smooth, so be mindful when adjusting this parameter.
-- If the mesh seems wrong, try increasing the resolution slider before suspecting a bug in the code.

-- Every fuction and variable in this script is commented to explain the underlying geometry and implementation details.

-- The intersection_body is a feedback tool that computes the intersection of the two gear solids.
-- When the driven gear given an angular offset, this intersection body visualizes the contact condition between the flanks:
-- - No intersection: flanks not touching (positive backlash)
-- - Slight intersection: flanks just touching (zero backlash)
-- - Visible volume of intersection: flanks penetrating (negative backlash / interference)

-- -------------------------------------------------------------

-- The script is structured into 5 sections:

-- 1. UI Parameters: all adjustable parameters are defined here with sliders and toggles.
-- 2. Helper Functions: utility functions for math operations.
-- 3. Beveloid Gear Builder: the main function that constructs a single beveloid gear solid based on the Brauer rack-generation method.
-- 4. Assembly: builds the meshed gear pair based on the UI parameters.
--    This section also includes the shafts and shim, which can be toggled on/off.
-- 5. Intersection Body: computes the intersection of the two gears to visualize backlash conditions.

-- ============================================================
-- SECTION 1: UI PARAMETERS
-- ============================================================

-- ---- Gear geometry ----
local res                        = ui_number("Resolution", 10, 5, 50)                    -- Controls mesh resolution for all curve samplings
local m                          = ui_number("Module", 4.0, 1, 10.0)                    -- Gear module [mm]
local alpha_n_deg                = ui_number("Normal Pressure Angle (deg)", 20, 16, 24) -- Normal pressure angle in degrees

local alpha_n_rad                = alpha_n_deg * math.pi / 180.0
local x_min                      = -0.3 -- minimum profile shift coefficient (undercut limit)
local x_max                      = 1.0  -- maximum profile shift coefficient

-- ---- Minimum tooth count to prevent undercut ----
local sin_alpha_n                = math.sin(alpha_n_rad)
local zmin                       = math.ceil(2 * (x_max - x_min) / (sin_alpha_n * sin_alpha_n))
--
--local z_driving                  = ui_number("Number of Teeth-Driving Gear", zmin, zmin, 40)
--local z_driven                   = ui_number("Number of Teeth-Driven Gear ", zmin, zmin, 40)

local z_driving = 22
local z_driven = 22
local b                          = ui_number("Face Width (mm)", 15.0, 5.0, 30.0) -- Axial face width [mm]

-- ---- Profile shifts of Driving Gear ----
local x_coef_bottom_driving      = ui_scalar("Profile Shift Coefficient Bottom-Driving Gear", 1.0, x_min, x_max)
local x_coef_top_driving         = ui_scalar("Profile Shift Coefficient Top-Driving Gear", x_min, x_min, x_max)

-- ---- Profile shifts of Driven Gear (can be different from Driving Gear) ----
local x_coef_bottom_driven       = ui_scalar("Profile Shift Coefficient Bottom-Driven Gear", 1.0, x_min, x_max)
local x_coef_top_driven          = ui_scalar("Profile Shift Coefficient Top-Driven Gear", -0.3, x_min, x_max)

-- ---- Tooth geometry coefficients ----
local h_a_coef                   = 1.25                                             -- Addendum height coefficient (ISO standard: 1.25*m)
local h_a                        = h_a_coef * m                                     -- Addendum height [mm]

local rho_coef                   = ui_scalar("Fillet Coefficient", 0.38, 0.05, 0.8) -- coefficient of tip radius of generating rack
local rho                        = rho_coef * m                                     -- tip radius of generating rack [mm]

-- ---- Assembly controls ----
local shim_thickness             = ui_number("Shim thickness (mm)", b/2, 0, b)                                       -- Axial spacer thickness under driven gear [mm]
local gear_rotation              = ui_scalar("Driving Gear Rotation (Anti-Clockwise direction) (deg)", 0, 0, 90.0) -- Driving Gear rotation angle [deg]

-- ---- Shaft parameters ----
local shaft_dia                  = ui_number("Shaft diameter (mm)", 17.0, 10.0, 60.0) -- Shaft diameter [mm]
local shaft_height               = ui_scalar("Shaft Height (mm)", 6.0, 1.0, 30.0)     -- Shaft overhang above/below gear face [mm]

-- ---- Backlash demonstration ----
-- Rotates ONLY the driven gear so backlash can be probed
local driven_gear_angular_offset = ui_scalar("Driven Gear angular offset (deg)", 0, -2.0, 2.0)

-- ---- Visualization toggles & clearance ----
local clearance                  = ui_scalar("Clearance (mm)", 4.0, 0.0, 5.0) -- Clearance between gear [mm]
local show_shim_disk             = ui_bool("Show Shim Disk", true)            -- Show physical shim spacer
local show_shafts                = ui_bool("Show Shafts", true)               -- Show shaft cylinders
local show_driving_gear          = ui_bool("Show Driving Gear", true)          -- Show driving gear body
local show_driven_gear           = ui_bool("Show Driven Gear", true) 
local show_intersection          = ui_bool("Show Intersection Body", false)   -- Highlight overlapping volume (backlash probe)
local show_wooden_plate          = ui_bool("Show Wooden Plate (fixed dimensions)", false)         -- Show wooden base plate under the gears (for better visibility of clearance)

-- ============================================================
-- SECTION 2: HELPER FUNCTIONS
-- ============================================================

-- Returns b if a < b, otherwise a  (one-sided clamp)
local function clamp_min(a, b)
  if a < b then return b else return a end
end

-- Floating-point modulo  (always non-negative for positive b)
local function mod(a, b)
  return a - math.floor(a / b) * b
end

-- Cotangent
local function cot(x)
  return math.cos(x) / math.sin(x)
end

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
  if i2 < i1 then return end
  for i = i1, i2 do
    dst[#dst + 1] = src[i]
  end
end

-- Append arrays: source[i1..i2] (reversed) to the end of destination
local function append_reverse_range(dst, src, i1, i2)
  if i2 < i1 then return end
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

-- Screw
local screw_height = 16
local screwHole_dia = 1.8
local hole_radius = screwHole_dia / 2
local screw_thread_height = 11
local screwHead_dia = 4.8
local screwHead_height = screw_height - screw_thread_height - 1
local total_screw_length = screwHead_height + screw_thread_height
screwHead = cone(hole_radius, screwHead_dia/2, screwHead_height)
screwThread = cylinder(hole_radius, screw_thread_height)

local screw = union(translate(0, 0, screw_thread_height) * screwHead,
                    translate(0, 0, 0) * screwThread)

--mount
local mount_height = 5
local mount_length = 2.5*shaft_dia
local mount = translate(0, 0, 0) * cube(mount_length, mount_length, mount_height)
local screw1 = translate(mount_length/3, mount_length/3, -total_screw_length+mount_height) * screw
local screw2 = translate(-mount_length/3, mount_length/3, -total_screw_length+mount_height) * screw
local screw3 = translate(-mount_length/3, -mount_length/3, -total_screw_length+mount_height) * screw
local screw4 = translate(mount_length/3, -mount_length/3, -total_screw_length+mount_height) * screw

local screws = union({screw1, screw2, screw3, screw4})
mount = difference(mount, screws)
-- emit(mount, 4)

-- Shafts
local function make_shaft(shaft_h)
  local r = shaft_dia / 2
  local h = 2 * b + 2 * shaft_h -- total shaft length
  local shaft = translate(0, 0, -shaft_h) * cylinder(r, h)
  -- key = translate(0, -r, -shaft_height) * cube(r / 2, r / 2, h)
  -- shaft = rotate(-90, v(0, 0, 1)) * union(shaft, key)
  local mnt = translate(0, 0, -mount_height-shaft_h) * mount
  shaft = translate(0, 0, shaft_h) * union(shaft, mnt)
  -- emit (shaft, 5)
  return shaft
end

local num_layers   = res -- number of cross-section layers along the face width
local res_fillet   = res -- sample points along each fillet arc
local res_involute = res -- sample points along each involute curve
local res_arcs     = res -- sample points for top-land and bottom-land arcs


-- ============================================================
-- SECTION 3: BEVELOID GEAR
-- ============================================================
-- Builds a single beveloid gear solid as an IceSL polyhedron.

-- Parameters:
--   z_local   : number of teeth
--   x_bottom  : profile shift coefficient at z = 0 (bottom face)
--   x_top     : profile shift coefficient at z = b (top face)

-- ============================================================
function make_beveloid(z_local, x_bottom, x_top)
  local delta = math.atan((m * (x_top - x_bottom)) / b) -- The beveloid cone angle delta is derived from the profile-shift
  z_local     = clamp_min(z_local, zmin)

  -- ----------------------------------------------------------
  -- Inner function: 2-D tooth contour at one axial cross-section
  -- x_local is the profile shift coefficient at this slice
  -- Returns two arrays (contour_x, contour_y) for all z_local teeth
  -- ----------------------------------------------------------
  local function build_layer_contour(x_local)
    -- Transverse pressure angle at this slice (affected by cone angle)
    local alpha_t  = math.atan(math.tan(alpha_n_rad) * math.cos(delta))
    local r_p      = z_local * m / 2.0                                       -- pitch radius
    local r_b      = r_p * math.cos(alpha_t)                                 -- base circle radius
    local s_t      = m * (math.pi / 2.0 + 2.0 * x_local * math.tan(alpha_t)) -- tooth thickness on pitch circle
    local x_n      = x_local * math.cos(delta)                               -- normal-plane profile shift
    local r_f      = r_p + x_local * m - h_a / math.cos(delta)               -- root circle radius
    local r_a      = r_p + m * (1.0 + x_local)                               -- addendum circle radius

    -- ---- Undercut check ----
    local lhs      = r_b * math.tan(alpha_t)
    local rhs      = (h_a - x_n * m - rho * (1.0 - math.sin(alpha_n_rad))) /
        (math.sin(alpha_t) * math.cos(delta))
    local undercut = lhs < rhs -- true => undercut condition detected

    -- Fillet/involute junction point (polar coords: r_IF, psi_IF)
    local r_IF   -- radius at which the involute and fillet meet (in polar coordinates)
    local psi_IF -- angle at which the involute and fillet meet (in polar coordinates)
    if not undercut then
      local term = r_b * math.tan(alpha_t) -
          (h_a - x_n * m - rho * (1.0 - math.sin(alpha_n_rad))) /
          (math.sin(alpha_t) * math.cos(delta))
      r_IF       = math.sqrt(math.max(r_b * r_b + term * term, 0.0))
      psi_IF     = alpha_t
    else
      -- Fallback parameters for undercut
      r_IF   = r_b
      psi_IF = alpha_t
    end

    -- ==========================================
    -- Fillet Profile
    -- ==========================================

    -- Right-flank fillet
    local filletR_x, filletR_y = {}, {}
    local psi_vals = linspace(psi_IF, math.pi / 2.0, res_fillet)
    for i = 1, #psi_vals do
      local psi                 = psi_vals[i]
      local psi_n               = math.atan(math.tan(psi) / math.cos(delta))
      local A                   = (h_a - x_n * m - rho * (1.0 - math.sin(psi_n))) /
          math.cos(delta)           -- shorthand for Common term in brackets
      local phi_f               = ( -- Angular position of the rack contact point on the pitch circle
        A * cot(psi) +
        (math.pi * m / 4.0) +
        h_a * math.tan(alpha_n_rad) +
        rho * (((1.0 - math.sin(alpha_n_rad)) / math.cos(alpha_n_rad)) - math.cos(psi_n))
      ) / r_p

      local xi_F                = r_p * math.sin(phi_f) -
          (A / math.sin(psi)) *
          math.cos(psi - phi_f) -- abscissa of fillet point
      local eta_F               = r_p * math.cos(phi_f) -
          (A / math.sin(psi)) *
          math.sin(psi - phi_f) -- ordinate of fillet point

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

    local phi_r_b        = s_t / (2.0 * r_p) + math.tan(alpha_t)                -- Roll angle at pitch point
    local phi_r_a        = phi_r_b - math.sqrt((r_a * r_a) / (r_b * r_b) - 1.0) -- Roll angle at tip circle
    local phi_r_IF       = phi_r_b -
        math.sqrt((r_IF * r_IF) / (r_b * r_b) - 1.0)                            -- Roll angle at fillet/involute junction

    -- Right-flank involute: from tip (phi_r_a) down to junction (phi_r_IF)
    local invR_x, invR_y = {}, {}
    local phi_vals       = linspace(phi_r_a, phi_r_IF, res_involute)
    for i = 1, #phi_vals do
      local phi_i         = phi_vals[i]
      local xi_I          = r_p * math.sin(phi_i) -
          ((r_p * phi_i - s_t / 2.0) * math.cos(alpha_t)) *
          math.cos(phi_i - alpha_t) -- abscissa of involute point
      local eta_I         = r_p * math.cos(phi_i) +
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
    local phi_top_land_start = math.atan2(invR_y[1], invR_x[1])             -- starting angle of top-land arc (from right involute end point)
    local phi_top_land_end   = math.atan2(invL_y[#invL_y], invL_x[#invL_x]) -- ending angle of top-land arc (from left involute end point)
    while phi_top_land_end < phi_top_land_start do
      phi_top_land_end = phi_top_land_end + 2.0 * math.pi
    end

    local x_top_land_arc = {}                                                     -- abcissa of top-land arc points
    local y_top_land_arc = {}                                                     -- ordinate of top-land arc points
    local phi_top_land = linspace(phi_top_land_start, phi_top_land_end, res_arcs) -- angles for sampling the top-land arc

    for i = 1, #phi_top_land do
      x_top_land_arc[#x_top_land_arc + 1] = r_a * math.cos(phi_top_land[i])
      y_top_land_arc[#y_top_land_arc + 1] = r_a * math.sin(phi_top_land[i])
    end

    -- ==========================================
    -- Bottom-Land Arc
    -- ==========================================
    local pitch_angle          = 2.0 * math.pi /
        z_local                                                                                          -- angular pitch between teeth
    local phi_bottom_land_L    = math.atan2(filletL_y[1], filletL_x[1])                                  -- starting angle of bottom-land arc
    local phi_bottom_land_R    = math.atan2(filletR_y[#filletR_y], filletR_x[#filletR_x])                -- ending angle of bottom-land arc
    local phi_root_land_R_next = phi_bottom_land_R +
        pitch_angle                                                                                      -- next right flank (of next tooth) defines the end of the bottom land for this tooth
    local d_phi_bottom         = mod(phi_root_land_R_next - phi_bottom_land_L, 2.0 * math.pi)            -- angle spanned by the bottom land arc, wrapped to [0, 2pi]

    local x_bottom_arc         = {}                                                                      -- abcissa of bottom-land arc points
    local y_bottom_arc         = {}                                                                      -- ordinate of bottom-land arc points
    local phi_bottom_land      = linspace(phi_bottom_land_L, phi_bottom_land_L + d_phi_bottom, res_arcs) -- angles for sampling the bottom-land arc

    for i = 1, #phi_bottom_land do
      x_bottom_arc[#x_bottom_arc + 1] = r_f * math.cos(phi_bottom_land[i])
      y_bottom_arc[#y_bottom_arc + 1] = r_f * math.sin(phi_bottom_land[i])
    end

    -- ==========================================
    -- Single Tooth-Pitch Contour
    -- Ordering: right-fillet -> right-involute -> top-land -> left-involute -> left-fillet -> bottom-land
    -- ==========================================
    local x_pitch, y_pitch = {}, {}

    -- Appending arrays in clockwise direction around the tooth profile
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
    local theta_pitch, r_pitch = cart2pol(x_pitch, y_pitch) -- convert single-tooth contour to polar coordinates
    local contour_x = {}                                    -- abcissa of the full layer contour (all teeth)
    local contour_y = {}                                    -- ordinate of the full layer contour (all teeth)

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

  local pts_per_layer = 0                                     -- placeholder for number of points in each layer

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

  local gear_solid = polyhedron(points, faces)
  return gear_solid
end -- end make_beveloid

-- ============================================================
-- SECTION 4: ASSEMBLY
-- ============================================================

-- ---- Operating center distance ----
local r_p_driving              = (z_driving * m) / 2      -- pitch radius of the driving gear
local r_p_driven               = (z_driven * m) / 2       -- pitch radius of the driven gear
local standard_center_distance = r_p_driving + r_p_driven -- center distance without profile shift or clearance

-- Use the mid-face profile shift of each gear to compute the shift correction
local driving_x_mid            = (x_coef_bottom_driving + x_coef_top_driving) / 2.0   -- mid-face profile shift coefficient of driving gear
local driven_x_mid             = (x_coef_bottom_driven + x_coef_top_driven) / 2.0     -- mid-face profile shift coefficient of driven gear
local sum_x                    = driving_x_mid + driven_x_mid                         -- total mid-face profile shift coefficient

-- Adjust center distance based on total profile shift and optional visual clearance
local operating_center_dist   = standard_center_distance 
                              * (math.cos(alpha_n_rad) / math.cos(alpha_n_rad)) 
                              + clearance 
                              + (sum_x * m)

-- ---- Angular phase and gear ratio ----
local phase_offset             = 180 / z_driven         -- half-tooth offset so flanks mesh (not tip-to-tip)
local gear_ratio               = z_driving / z_driven

-- ---- Build raw gear bodies ----
local driving_gear             = make_beveloid(z_driving, x_coef_bottom_driving, x_coef_top_driving)
local driven_gear              = make_beveloid(z_driven, x_coef_bottom_driven, x_coef_top_driven)

-- ---- Subtract shaft bores from each gear ----
local driving_gear             = difference(driving_gear, translate(0, 0, -b) * make_shaft(shaft_height))
local driven_gear              = difference(driven_gear, translate(0, 0, -b) * make_shaft(shaft_height))

-- ---- Assembly transforms ----

-- Driving gear
local meshed_driving_gear     = translate(0, 0, shim_thickness) 
                              * rotate(gear_rotation - 90, v(0, 0, 1)) 
                              * driving_gear --rotate -90 deg so a tooth tip aligns with +X (towards the driven gear)

-- Driven gear:

local meshed_driven_gear       = translate(operating_center_dist, 0, 2*b)
    * rotate(180, v(0, 1, 0)) -- rotate 180 deg around Y  ->  flips the taper so both gears face each other
    * rotate(phase_offset + (gear_rotation * gear_ratio) - driven_gear_angular_offset - 90, v(0, 0, 1))
    * driven_gear
-- apply phase offset + synced ratio rotation + backlash probe offset
-- translate to operating center distance, and axially offset by face width + shim

-- ============================================================
-- SHAFTS
-- ============================================================

driving_shaft   = make_shaft(shaft_height)

driven_shaft  = translate(operating_center_dist, 0, 0) 
                * make_shaft(shaft_height)
driven_shaft_modification = cylinder((3 * shaft_dia) / 4, b) 
driven_shaft = union(driven_shaft, translate(operating_center_dist, 0, 0) * driven_shaft_modification)

shim_holder  = translate(operating_center_dist, 3*operating_center_dist/4, 0) 
        * make_shaft(0)

if show_shafts then
  if not show_intersection then -- hide shafts when intersection mode is active
    emit(driving_shaft, 12)
    emit(driven_shaft, 12)
    emit(shim_holder, 12)
  end
end

-- ============================================================
-- SHIM
-- ============================================================


if show_shim_disk and shim_thickness > 0 then
  if not show_intersection then
    local r_shim = 3 * shaft_dia / 4.0 + 2.5                                                -- slightly larger than shaft radius for better visibility 
    local shim   = translate(0, 0, 0) * cylinder(r_shim, shim_thickness)
    shim         = difference(shim, driving_shaft)                                                 -- cut shaft bore through the disk
    local diff_cube = translate(0, -shaft_dia, 0) * cube(shaft_dia, 2 * shaft_dia, shim_thickness) -- helper cube for cutting the bore (to ensure a clean cut)
    shim = difference(shim, diff_cube)
    emit(shim, 6)
  end
end

-- ============================================================
-- BASE PLATE
-- ============================================================

-- Tip radius of driving gear 
local X1_max       = math.max(x_coef_bottom_driving, x_coef_top_driving)
local ra1          = (z_driving * m / 2.0) + m * (1.0 + X1_max)

-- Tip radius of driven gear
local X2_max       = math.max(x_coef_bottom_driven, x_coef_top_driven)
local ra2          = (z_driven * m / 2.0) + m * (1.0 + X2_max)

local margin       = 5.0 -- padding around outermost geometry [mm]

-- X extent: from the far side of driving gears to the far side of driven gear
local plate_x_min  = -ra1 - margin
local plate_x_max  = operating_center_dist + ra2 + margin
local plate_w      = plate_x_max - plate_x_min

-- Y extent: symmetric, decided by the larger of the two tip radii
local plate_half_d = math.max(ra1, ra2) + margin
local plate_d      = 2.0 * plate_half_d + operating_center_dist/3

local p_thick      = 1.0  -- plate thickness [mm]

-- Centre the plate in X so it spans [plate_x_min, plate_x_max]
basePlate          = translate(plate_x_min + plate_w / 2.0, operating_center_dist/6, -mount_height - p_thick)
    * cube(plate_w, plate_d, p_thick)

if not show_wooden_plate then
  -- emit(basePlate, 1)
end


local wood_length = 210.0
local wood_breadth = 148.0
local wood_height = 9.0

wooden_plate =  translate(operating_center_dist/2, operating_center_dist/6, -mount_height - wood_height) * cube(wood_length, wood_breadth, wood_height)

if show_wooden_plate then
  emit(wooden_plate, 5)
end

-- ============================================================
-- SECTION 5: INTERSECTION BODY
-- ============================================================

-- Empty                -> flanks not touching 
-- Slight intersection  -> flanks just touching
-- Volume               -> flanks penetrating 

print(string.format("%d", operating_center_dist))

local intersection_body
if show_intersection then
  intersection_body = intersection(meshed_driving_gear, meshed_driven_gear)
  local bb = bbox(intersection_body)
  if bb:empty() then
    print("No intersection found") -- gears not touching
  else
    emit(intersection_body, 70)    
  end
else
  if show_driving_gear then
    emit(meshed_driving_gear, 45)
  end
  if show_driven_gear then
    emit(meshed_driven_gear, 55)
  end
end
