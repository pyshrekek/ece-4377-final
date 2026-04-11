LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

PACKAGE GRAPHICS_TEST_UTILS IS

    FUNCTION is_on_line (
        x, y, x0, y0, x1, y1, thickness : INTEGER
    ) RETURN BOOLEAN;

    FUNCTION is_on_cube (
        x, y, center_x, center_y, side_length : INTEGER
    ) RETURN BOOLEAN;

END PACKAGE GRAPHICS_TEST_UTILS;

PACKAGE BODY GRAPHICS_TEST_UTILS IS

    FUNCTION is_on_line (
        x, y, x0, y0, x1, y1, thickness : INTEGER
    ) RETURN BOOLEAN IS
        VARIABLE dx, dy, ex, ey, dot, len_sq, cross_product : INTEGER;
        VARIABLE cross_product_squared, max_allowed_cross_squared : signed(63 DOWNTO 0);
        VARIABLE thickness_sq : INTEGER;
    BEGIN
        dx := x1 - x0;
        dy := y1 - y0;
        ex := x - x0;
        ey := y - y0;
        cross_product := ex * dy - ey * dx;
        dot := ex * dx + ey * dy;
        len_sq := dx * dx + dy * dy;

        IF len_sq = 0 THEN
            RETURN false;
        END IF;

        thickness_sq := thickness * thickness;
        cross_product_squared := to_signed(cross_product, 32) * to_signed(cross_product, 32);
        max_allowed_cross_squared := to_signed(thickness_sq, 32) * to_signed(len_sq, 32);

        RETURN (cross_product_squared <= max_allowed_cross_squared)
        AND (dot >= 0)
        AND (dot <= len_sq);
    END FUNCTION;

    FUNCTION is_on_cube (
        x, y, center_x, center_y, side_length : INTEGER
    ) RETURN BOOLEAN IS
        CONSTANT half_side : INTEGER := side_length / 2;
        CONSTANT depth_x : INTEGER := side_length / 3;
        CONSTANT depth_y : INTEGER := -side_length / 4;

        CONSTANT f0_x : INTEGER := center_x - half_side;
        CONSTANT f0_y : INTEGER := center_y - half_side;
        CONSTANT f1_x : INTEGER := center_x + half_side;
        CONSTANT f1_y : INTEGER := center_y - half_side;
        CONSTANT f2_x : INTEGER := center_x + half_side;
        CONSTANT f2_y : INTEGER := center_y + half_side;
        CONSTANT f3_x : INTEGER := center_x - half_side;
        CONSTANT f3_y : INTEGER := center_y + half_side;

        CONSTANT b0_x : INTEGER := f0_x + depth_x;
        CONSTANT b0_y : INTEGER := f0_y + depth_y;
        CONSTANT b1_x : INTEGER := f1_x + depth_x;
        CONSTANT b1_y : INTEGER := f1_y + depth_y;
        CONSTANT b2_x : INTEGER := f2_x + depth_x;
        CONSTANT b2_y : INTEGER := f2_y + depth_y;
        CONSTANT b3_x : INTEGER := f3_x + depth_x;
        CONSTANT b3_y : INTEGER := f3_y + depth_y;
    BEGIN
        RETURN
            is_on_line(x, y, f0_x, f0_y, f1_x, f1_y, 1) OR
            is_on_line(x, y, f1_x, f1_y, f2_x, f2_y, 1) OR
            is_on_line(x, y, f2_x, f2_y, f3_x, f3_y, 1) OR
            is_on_line(x, y, f3_x, f3_y, f0_x, f0_y, 1) OR
            is_on_line(x, y, b0_x, b0_y, b1_x, b1_y, 1) OR
            is_on_line(x, y, b1_x, b1_y, b2_x, b2_y, 1) OR
            is_on_line(x, y, b2_x, b2_y, b3_x, b3_y, 1) OR
            is_on_line(x, y, b3_x, b3_y, b0_x, b0_y, 1) OR
            is_on_line(x, y, f0_x, f0_y, b0_x, b0_y, 1) OR
            is_on_line(x, y, f1_x, f1_y, b1_x, b1_y, 1) OR
            is_on_line(x, y, f2_x, f2_y, b2_x, b2_y, 1) OR
            is_on_line(x, y, f3_x, f3_y, b3_x, b3_y, 1);
    END FUNCTION;

END PACKAGE BODY GRAPHICS_TEST_UTILS;