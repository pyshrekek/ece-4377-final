-- ============================================================
-- DEFINE_OBJECTS.vhd
-- ECE 4377 Final Project
--
-- Central scene description. Edit this file to add, move, or
-- recolour cubes and to adjust the light without touching
-- GRAPHICS_LAYER or RENDERING_PIPELINE.
--
-- cube_t fields (defined in RENDERING_PIPELINE):
--   center_x, center_y  : screen-space centre (pixels)
--   side_length          : full side length (pixels)
--   color                : RGB 8-bit per channel
--
-- light_t fields (defined in RENDERING_PIPELINE):
--   x_q8, y_q8, z_q8    : light direction, Q8 integers
--   ambient_q8           : ambient term  (0-255)
--   diffuse_q8           : diffuse scale (0-255)
--
-- To add a cube: increment NUM_CUBES and append a SCENE entry.
-- To hide one:   set side_length => 0  (zero-size = invisible).
-- ============================================================

library ieee;
  use ieee.std_logic_1164.all;
  use work.graphics_test_utils.all;
  use work.rendering_pipeline.all;

package define_objects is

  -- ── Light ────────────────────────────────────────────────
  -- Direction roughly upper-left-front; change x/y/z_q8 to
  -- move the light source.
  constant scene_light : light_t :=
  (
    x_q8       => 160,
    y_q8       => 110,
    z_q8       => 220,
    ambient_q8 => 48,
    diffuse_q8 => 192
  );

  constant background_color : color_t :=
  (
    r => x"00",
    g => x"00",
    b => x"00"
  );

  -- ── Cubes ────────────────────────────────────────────────
  constant num_cubes : INTEGER := 3;

  type scene_t is array (0 to NUM_CUBES - 1) of cube_t;

  constant scene : scene_t :=
  (
    -- index 0: large white cube, left-center (highest priority)
    0 => (center_x    => 280,              center_y    => 240,              side_length => 160,              color       => (r => x"FF", g => x"FF", b => x"FF")),

    -- index 1: medium cyan cube
    1 => (center_x    => 460,              center_y    => 240,              side_length => 120,              color       => (r => x"00", g => x"FF", b => x"FF")),

    -- index 2: small red cube
    2 => (center_x    => 500,              center_y    => 240,              side_length => 100,              color       => (r => x"FF", g => x"00", b => x"00"))
  );

end package define_objects;
