-- ============================================================
-- SPHERE_RENDERING.vhd
-- ECE 4377 Final Project
--
-- Sphere object type + per-pixel lit sphere renderer.
-- Keep sphere-specific logic here so scene wiring stays clean.
-- ============================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.graphics_test_utils.all;
  use work.rendering_pipeline.all;

package sphere_rendering is

  type sphere_t is record
    center_x : integer;
    center_y : integer;
    radius   : integer;
    color    : color_t;
  end record;

  function render_lit_sphere_pixel(
    x, y   : integer;
    sphere : sphere_t;
    light  : light_t
  ) return color_t;

end package sphere_rendering;

package body sphere_rendering is

  function clamp_u8(v : integer) return integer is
  begin
    if v < 0 then
      return 0;
    elsif v > 255 then
      return 255;
    end if;
    return v;
  end function;

  function to_slv8(v : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(clamp_u8(v), 8));
  end function;

  function scale_color(base_color : color_t; shade_q8 : integer) return color_t is
    variable base_r : integer;
    variable base_g : integer;
    variable base_b : integer;
  begin
    base_r := to_integer(unsigned(base_color.r));
    base_g := to_integer(unsigned(base_color.g));
    base_b := to_integer(unsigned(base_color.b));

    return (
      r => to_slv8((base_r * shade_q8) / 255),
      g => to_slv8((base_g * shade_q8) / 255),
      b => to_slv8((base_b * shade_q8) / 255)
    );
  end function;

  function int_sqrt(n : integer) return integer is
    variable r : integer := 0;
  begin
    if n <= 0 then
      return 0;
    end if;

    while ((r + 1) * (r + 1)) <= n loop
      r := r + 1;
    end loop;
    return r;
  end function;

  function render_lit_sphere_pixel(
    x, y   : integer;
    sphere : sphere_t;
    light  : light_t
  ) return color_t is
    variable dx      : integer;
    variable dy      : integer;
    variable radius2 : integer;
    variable dist2   : integer;
    variable z       : integer;
    variable nx_q8   : integer;
    variable ny_q8   : integer;
    variable nz_q8   : integer;
    variable dot_q8  : integer;
    variable shade   : integer;
  begin
    if sphere.radius <= 0 then
      return TRANSPARENT;
    end if;

    dx := x - sphere.center_x;
    dy := y - sphere.center_y;
    radius2 := sphere.radius * sphere.radius;
    dist2 := dx * dx + dy * dy;

    if dist2 > radius2 then
      return TRANSPARENT;
    end if;

    z := int_sqrt(radius2 - dist2);

    nx_q8 := (dx * 255) / sphere.radius;
    ny_q8 := (dy * 255) / sphere.radius;
    nz_q8 := (z * 255) / sphere.radius;

    dot_q8 := ((nx_q8 * light.x_q8) + (ny_q8 * light.y_q8) + (nz_q8 * light.z_q8)) / 255;
    if dot_q8 < 0 then
      dot_q8 := 0;
    end if;

    shade := light.ambient_q8 + ((dot_q8 * light.diffuse_q8) / 255);
    return scale_color(sphere.color, clamp_u8(shade));
  end function;

end package body sphere_rendering;
