LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE work.GRAPHICS_TEST_UTILS.ALL;
USE work.transforms.ALL;

PACKAGE RENDERING_PIPELINE IS

    TYPE cube_t IS RECORD
        center_x : INTEGER;
        center_y : INTEGER;
        side_length : INTEGER;
        scale_x_q8 : INTEGER; -- 256 = 1.0x
        scale_y_q8 : INTEGER; -- 256 = 1.0x
        rotation_x : angle_t; -- 0..255 maps to 0..360°, tilt around local X
        rotation_y : angle_t; -- 0..255 maps to 0..360°, tilt around local Y
        rotation_z : angle_t; -- 0..255 maps to 0..360°, rotates about cube center
        color : color_t;
    END RECORD;
    TYPE cube_scene_t IS ARRAY (NATURAL RANGE <>) OF cube_t;

    TYPE light_t IS RECORD
        x_q8 : INTEGER;
        y_q8 : INTEGER;
        z_q8 : INTEGER;
        ambient_q8 : INTEGER;
        diffuse_q8 : INTEGER;
    END RECORD;

    -- Shared triangle primitive used across shape renderers.
    TYPE triangle_t IS RECORD
        x1 : INTEGER;
        y1 : INTEGER;
        x2 : INTEGER;
        y2 : INTEGER;
        x3 : INTEGER;
        y3 : INTEGER;
        normal_x_q8 : INTEGER;
        normal_y_q8 : INTEGER;
        normal_z_q8 : INTEGER;
    END RECORD;
    TYPE triangle_scene_t IS ARRAY (NATURAL RANGE <>) OF triangle_t;

    -- Shared fixed-point pixel helpers used by primitive renderers.
    FUNCTION clamp_u8(v : INTEGER) RETURN INTEGER;
    FUNCTION inv_scale_delta_q8(delta_px, scale_q8 : INTEGER) RETURN INTEGER;
    FUNCTION scale_color(base_color : color_t; shade_q8 : INTEGER) RETURN color_t;
    FUNCTION shade_from_dot_q8(dot_q8 : INTEGER; light : light_t) RETURN INTEGER;
    FUNCTION shade_from_normal_q8(
        normal_x_q8, normal_y_q8, normal_z_q8 : INTEGER;
        light : light_t
    ) RETURN INTEGER;
    FUNCTION render_lit_triangle_pixel(
        x, y : INTEGER;
        tri : triangle_t;
        base_color : color_t;
        light : light_t
    ) RETURN color_t;
    FUNCTION render_lit_triangle_scene_pixel(
        x, y : INTEGER;
        triangles : triangle_scene_t;
        base_color : color_t;
        light : light_t
    ) RETURN color_t;

    FUNCTION render_lit_cube_pixel(
        x, y : INTEGER;
        cube : cube_t;
        light : light_t
    ) RETURN color_t;

END PACKAGE RENDERING_PIPELINE;

PACKAGE BODY RENDERING_PIPELINE IS

    FUNCTION div_round_signed(num, den : INTEGER) RETURN INTEGER IS
    BEGIN
        IF den = 0 THEN
            RETURN 0;
        END IF;

        IF num >= 0 THEN
            RETURN (num + (den / 2)) / den;
        ELSE
            RETURN -(((-num) + (den / 2)) / den);
        END IF;
    END FUNCTION;

    FUNCTION clamp_u8(v : INTEGER) RETURN INTEGER IS
    BEGIN
        IF v < 0 THEN
            RETURN 0;
        ELSIF v > 255 THEN
            RETURN 255;
        END IF;
        RETURN v;
    END FUNCTION;

    FUNCTION to_slv8(v : INTEGER) RETURN STD_LOGIC_VECTOR IS
    BEGIN
        RETURN STD_LOGIC_VECTOR(to_unsigned(clamp_u8(v), 8));
    END FUNCTION;

    FUNCTION is_transparent(c : color_t) RETURN BOOLEAN IS
    BEGIN
        RETURN (c.r = x"00") AND (c.g = x"00") AND (c.b = x"00");
    END FUNCTION;

    FUNCTION scale_color(base_color : color_t; shade_q8 : INTEGER) RETURN color_t IS
        VARIABLE base_r : INTEGER;
        VARIABLE base_g : INTEGER;
        VARIABLE base_b : INTEGER;
        VARIABLE shade  : INTEGER;
    BEGIN
        base_r := to_integer(unsigned(base_color.r));
        base_g := to_integer(unsigned(base_color.g));
        base_b := to_integer(unsigned(base_color.b));
        shade := clamp_u8(shade_q8);

        RETURN (
            -- Match SPHERE_RENDERING scale behavior for consistent shading.
            r => to_slv8((base_r * shade + 128) / 256),
            g => to_slv8((base_g * shade + 128) / 256),
            b => to_slv8((base_b * shade + 128) / 256)
        );
    END FUNCTION;

    FUNCTION shade_from_dot_q8(dot_q8 : INTEGER; light : light_t) RETURN INTEGER IS
        VARIABLE dot_clamped : INTEGER;
    BEGIN
        dot_clamped := clamp_u8(dot_q8);
        RETURN clamp_u8(light.ambient_q8 + ((dot_clamped * light.diffuse_q8 + 128) / 256));
    END FUNCTION;

    FUNCTION shade_from_normal_q8(
        normal_x_q8, normal_y_q8, normal_z_q8 : INTEGER;
        light : light_t
    ) RETURN INTEGER IS
        VARIABLE dot_q8 : INTEGER;
    BEGIN
        dot_q8 := (
            (normal_x_q8 * light.x_q8) +
            (normal_y_q8 * light.y_q8) +
            (normal_z_q8 * light.z_q8) +
            128
        ) / 256;
        RETURN shade_from_dot_q8(dot_q8, light);
    END FUNCTION;

    FUNCTION clamp_scale_q8(scale_q8 : INTEGER) RETURN INTEGER IS
    BEGIN
        IF scale_q8 < 1 THEN
            RETURN 1;
        END IF;
        RETURN scale_q8;
    END FUNCTION;

    FUNCTION inv_scale_delta_q8(delta_px, scale_q8 : INTEGER) RETURN INTEGER IS
        VARIABLE s : INTEGER;
    BEGIN
        s := clamp_scale_q8(scale_q8);
        IF s = 256 THEN
            RETURN delta_px;
        END IF;
        RETURN div_round_signed(delta_px * 256, s);
    END FUNCTION;

    FUNCTION min2(a, b : INTEGER) RETURN INTEGER IS
    BEGIN
        IF a < b THEN
            RETURN a;
        END IF;
        RETURN b;
    END FUNCTION;

    FUNCTION max2(a, b : INTEGER) RETURN INTEGER IS
    BEGIN
        IF a > b THEN
            RETURN a;
        END IF;
        RETURN b;
    END FUNCTION;

    TYPE normal_q8_t IS RECORD
        x : INTEGER;
        y : INTEGER;
        z : INTEGER;
    END RECORD;

    TYPE point3_t IS RECORD
        x : INTEGER;
        y : INTEGER;
        z : INTEGER;
    END RECORD;
    TYPE point3_scene_t IS ARRAY (NATURAL RANGE <>) OF point3_t;

    TYPE proj_point_t IS RECORD
        x : INTEGER;
        y : INTEGER;
        depth_q8 : INTEGER;
    END RECORD;
    TYPE proj_point_scene_t IS ARRAY (NATURAL RANGE <>) OF proj_point_t;

    TYPE cube_face_t IS RECORD
        i0 : INTEGER;
        i1 : INTEGER;
        i2 : INTEGER;
        i3 : INTEGER;
        normal_x_q8 : INTEGER;
        normal_y_q8 : INTEGER;
        normal_z_q8 : INTEGER;
    END RECORD;
    TYPE cube_face_scene_t IS ARRAY (NATURAL RANGE <>) OF cube_face_t;

    CONSTANT CAMERA_DIST_Q8 : INTEGER := 320 * 256;
    CONSTANT FOCAL_LEN_Q8   : INTEGER := 260 * 256;
    CONSTANT NEAR_PLANE_Q8  : INTEGER := 64 * 256;

    CONSTANT CUBE_FACES : cube_face_scene_t(0 TO 5) := (
        0 => (i0 => 0, i1 => 1, i2 => 2, i3 => 3, normal_x_q8 =>    0, normal_y_q8 =>    0, normal_z_q8 => -256), -- near/front
        1 => (i0 => 4, i1 => 5, i2 => 6, i3 => 7, normal_x_q8 =>    0, normal_y_q8 =>    0, normal_z_q8 =>  256), -- far/back
        2 => (i0 => 0, i1 => 3, i2 => 7, i3 => 4, normal_x_q8 => -256, normal_y_q8 =>    0, normal_z_q8 =>    0), -- left
        3 => (i0 => 1, i1 => 5, i2 => 6, i3 => 2, normal_x_q8 =>  256, normal_y_q8 =>    0, normal_z_q8 =>    0), -- right
        4 => (i0 => 0, i1 => 4, i2 => 5, i3 => 1, normal_x_q8 =>    0, normal_y_q8 => -256, normal_z_q8 =>    0), -- top
        5 => (i0 => 3, i1 => 2, i2 => 6, i3 => 7, normal_x_q8 =>    0, normal_y_q8 =>  256, normal_z_q8 =>    0)  -- bottom
    );

    FUNCTION rotate_normal_q8(
        nx, ny, nz : INTEGER;
        ax, ay, az : angle_t
    ) RETURN normal_q8_t IS
        VARIABLE cx : INTEGER;
        VARIABLE sx : INTEGER;
        VARIABLE cy : INTEGER;
        VARIABLE sy : INTEGER;
        VARIABLE cz : INTEGER;
        VARIABLE sz : INTEGER;
        VARIABLE x1, y1, z1 : INTEGER;
        VARIABLE x2, y2, z2 : INTEGER;
        VARIABLE out_n : normal_q8_t;
    BEGIN
        cx := to_integer(fp_cos(ax));
        sx := to_integer(fp_sin(ax));
        cy := to_integer(fp_cos(ay));
        sy := to_integer(fp_sin(ay));
        cz := to_integer(fp_cos(az));
        sz := to_integer(fp_sin(az));

        -- Rotate around X.
        x1 := nx;
        y1 := div_round_signed((cx * ny) - (sx * nz), 256);
        z1 := div_round_signed((sx * ny) + (cx * nz), 256);

        -- Rotate around Y.
        x2 := div_round_signed((cy * x1) + (sy * z1), 256);
        y2 := y1;
        z2 := div_round_signed(((-sy) * x1) + (cy * z1), 256);

        -- Rotate around Z.
        out_n.x := div_round_signed((cz * x2) - (sz * y2), 256);
        out_n.y := div_round_signed((sz * x2) + (cz * y2), 256);
        out_n.z := z2;
        RETURN out_n;
    END FUNCTION;

    FUNCTION scale_delta_q8(delta_px, scale_q8 : INTEGER) RETURN INTEGER IS
        VARIABLE s : INTEGER;
    BEGIN
        s := clamp_scale_q8(scale_q8);
        IF s = 256 THEN
            RETURN delta_px;
        END IF;
        RETURN div_round_signed(delta_px * s, 256);
    END FUNCTION;

    FUNCTION rotate_point_q8(
        px, py, pz : INTEGER;
        ax, ay, az : angle_t
    ) RETURN point3_t IS
        VARIABLE cx_q8 : INTEGER;
        VARIABLE sx_q8 : INTEGER;
        VARIABLE cy_q8 : INTEGER;
        VARIABLE sy_q8 : INTEGER;
        VARIABLE cz_q8 : INTEGER;
        VARIABLE sz_q8 : INTEGER;
        VARIABLE x1, y1, z1 : INTEGER;
        VARIABLE x2, y2, z2 : INTEGER;
        VARIABLE out_p : point3_t;
    BEGIN
        cx_q8 := to_integer(fp_cos(ax));
        sx_q8 := to_integer(fp_sin(ax));
        cy_q8 := to_integer(fp_cos(ay));
        sy_q8 := to_integer(fp_sin(ay));
        cz_q8 := to_integer(fp_cos(az));
        sz_q8 := to_integer(fp_sin(az));

        -- Rotate around X.
        x1 := px;
        y1 := div_round_signed((cx_q8 * py) - (sx_q8 * pz), 256);
        z1 := div_round_signed((sx_q8 * py) + (cx_q8 * pz), 256);

        -- Rotate around Y.
        x2 := div_round_signed((cy_q8 * x1) + (sy_q8 * z1), 256);
        y2 := y1;
        z2 := div_round_signed(((-sy_q8) * x1) + (cy_q8 * z1), 256);

        -- Rotate around Z.
        out_p.x := div_round_signed((cz_q8 * x2) - (sz_q8 * y2), 256);
        out_p.y := div_round_signed((sz_q8 * x2) + (cz_q8 * y2), 256);
        out_p.z := z2;
        RETURN out_p;
    END FUNCTION;

    FUNCTION project_point(
        px, py, pz : INTEGER;
        center_x, center_y : INTEGER
    ) RETURN proj_point_t IS
        VARIABLE out_p    : proj_point_t;
        VARIABLE depth_q8 : INTEGER;
    BEGIN
        depth_q8 := CAMERA_DIST_Q8 + (pz * 256);
        IF depth_q8 < NEAR_PLANE_Q8 THEN
            depth_q8 := NEAR_PLANE_Q8;
        END IF;

        out_p.x := center_x + div_round_signed(FOCAL_LEN_Q8 * px, depth_q8);
        out_p.y := center_y + div_round_signed(FOCAL_LEN_Q8 * py, depth_q8);
        out_p.depth_q8 := depth_q8;
        RETURN out_p;
    END FUNCTION;

    FUNCTION point_in_triangle_fast(
        px, py : INTEGER;
        x1, y1, x2, y2, x3, y3 : INTEGER
    ) RETURN BOOLEAN IS
        VARIABLE min_x : INTEGER;
        VARIABLE max_x : INTEGER;
        VARIABLE min_y : INTEGER;
        VARIABLE max_y : INTEGER;
    BEGIN
        min_x := min2(min2(x1, x2), x3);
        max_x := max2(max2(x1, x2), x3);
        min_y := min2(min2(y1, y2), y3);
        max_y := max2(max2(y1, y2), y3);

        IF (px < min_x) OR (px > max_x) OR (py < min_y) OR (py > max_y) THEN
            RETURN FALSE;
        END IF;
        RETURN is_point_in_triangle(px, py, x1, y1, x2, y2, x3, y3);
    END FUNCTION;

    FUNCTION render_lit_triangle_pixel(
        x, y : INTEGER;
        tri : triangle_t;
        base_color : color_t;
        light : light_t
    ) RETURN color_t IS
        VARIABLE shade_q8 : INTEGER;
    BEGIN
        IF point_in_triangle_fast(x, y, tri.x1, tri.y1, tri.x2, tri.y2, tri.x3, tri.y3) THEN
            shade_q8 := shade_from_normal_q8(tri.normal_x_q8, tri.normal_y_q8, tri.normal_z_q8, light);
            RETURN scale_color(base_color, shade_q8);
        END IF;
        RETURN TRANSPARENT;
    END FUNCTION;

    FUNCTION render_lit_triangle_scene_pixel(
        x, y : INTEGER;
        triangles : triangle_scene_t;
        base_color : color_t;
        light : light_t
    ) RETURN color_t IS
        VARIABLE pixel_color : color_t;
    BEGIN
        FOR tri_idx IN triangles'RANGE LOOP
            pixel_color := render_lit_triangle_pixel(x, y, triangles(tri_idx), base_color, light);
            IF NOT is_transparent(pixel_color) THEN
                RETURN pixel_color;
            END IF;
        END LOOP;
        RETURN TRANSPARENT;
    END FUNCTION;

    FUNCTION render_lit_cube_pixel(
        x, y : INTEGER;
        cube : cube_t;
        light : light_t
    ) RETURN color_t IS
        VARIABLE half_side : INTEGER;
        VARIABLE scale_z_q8 : INTEGER;
        VARIABLE local_vertices : point3_scene_t(0 TO 7);
        VARIABLE rotated_vertices : point3_scene_t(0 TO 7);
        VARIABLE projected_vertices : proj_point_scene_t(0 TO 7);
        VARIABLE face_n : normal_q8_t;
        VARIABLE face_shade_q8 : INTEGER;
        VARIABLE best_depth_sum : INTEGER := INTEGER'HIGH;
        VARIABLE depth_sum : INTEGER;
        VARIABLE best_color : color_t := TRANSPARENT;
        VARIABLE v0, v1, v2, v3 : proj_point_t;
    BEGIN
        IF cube.side_length <= 0 THEN
            RETURN TRANSPARENT;
        END IF;

        half_side := cube.side_length / 2;
        scale_z_q8 := (cube.scale_x_q8 + cube.scale_y_q8) / 2;

        -- Local cube vertices (y grows downward on screen; negative z is closer).
        local_vertices(0) := (x => -half_side, y => -half_side, z => -half_side);
        local_vertices(1) := (x =>  half_side, y => -half_side, z => -half_side);
        local_vertices(2) := (x =>  half_side, y =>  half_side, z => -half_side);
        local_vertices(3) := (x => -half_side, y =>  half_side, z => -half_side);
        local_vertices(4) := (x => -half_side, y => -half_side, z =>  half_side);
        local_vertices(5) := (x =>  half_side, y => -half_side, z =>  half_side);
        local_vertices(6) := (x =>  half_side, y =>  half_side, z =>  half_side);
        local_vertices(7) := (x => -half_side, y =>  half_side, z =>  half_side);

        FOR vert_idx IN 0 TO 7 LOOP
            rotated_vertices(vert_idx) := rotate_point_q8(
                scale_delta_q8(local_vertices(vert_idx).x, cube.scale_x_q8),
                scale_delta_q8(local_vertices(vert_idx).y, cube.scale_y_q8),
                scale_delta_q8(local_vertices(vert_idx).z, scale_z_q8),
                cube.rotation_x,
                cube.rotation_y,
                cube.rotation_z
            );
            projected_vertices(vert_idx) := project_point(
                rotated_vertices(vert_idx).x,
                rotated_vertices(vert_idx).y,
                rotated_vertices(vert_idx).z,
                cube.center_x,
                cube.center_y
            );
        END LOOP;

        FOR face_idx IN CUBE_FACES'RANGE LOOP
            face_n := rotate_normal_q8(
                CUBE_FACES(face_idx).normal_x_q8,
                CUBE_FACES(face_idx).normal_y_q8,
                CUBE_FACES(face_idx).normal_z_q8,
                cube.rotation_x,
                cube.rotation_y,
                cube.rotation_z
            );

            -- Back-face culling against camera looking along +Z.
            IF face_n.z < 0 THEN
                face_shade_q8 := shade_from_normal_q8(face_n.x, face_n.y, face_n.z, light);
                v0 := projected_vertices(CUBE_FACES(face_idx).i0);
                v1 := projected_vertices(CUBE_FACES(face_idx).i1);
                v2 := projected_vertices(CUBE_FACES(face_idx).i2);
                v3 := projected_vertices(CUBE_FACES(face_idx).i3);

                IF point_in_triangle_fast(x, y, v0.x, v0.y, v1.x, v1.y, v2.x, v2.y) THEN
                    depth_sum := v0.depth_q8 + v1.depth_q8 + v2.depth_q8;
                    IF depth_sum < best_depth_sum THEN
                        best_depth_sum := depth_sum;
                        best_color := scale_color(cube.color, face_shade_q8);
                    END IF;
                END IF;

                IF point_in_triangle_fast(x, y, v0.x, v0.y, v2.x, v2.y, v3.x, v3.y) THEN
                    depth_sum := v0.depth_q8 + v2.depth_q8 + v3.depth_q8;
                    IF depth_sum < best_depth_sum THEN
                        best_depth_sum := depth_sum;
                        best_color := scale_color(cube.color, face_shade_q8);
                    END IF;
                END IF;
            END IF;
        END LOOP;

        RETURN best_color;
    END FUNCTION;

END PACKAGE BODY RENDERING_PIPELINE;
