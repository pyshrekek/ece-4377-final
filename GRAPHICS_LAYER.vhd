LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE work.GRAPHICS_TEST_UTILS.ALL;
USE work.RENDERING_PIPELINE.ALL;

ENTITY GRAPHICS_LAYER IS
    PORT (
        pixel_row : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        pixel_column : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        vert_sync : IN STD_LOGIC;
        Red : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        Green : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        Blue : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
END ENTITY GRAPHICS_LAYER;

ARCHITECTURE behavioral OF GRAPHICS_LAYER IS

    SIGNAL x : INTEGER RANGE 0 TO 639;
    SIGNAL y : INTEGER RANGE 0 TO 639;

    -- Scene definition lives here; rendering implementation is in RENDERING_PIPELINE.
    CONSTANT SCENE_LIGHT : light_t := (
        x_q8 => 160,
        y_q8 => 110,
        z_q8 => 220,
        ambient_q8 => 48,
        diffuse_q8 => 192
    );

    CONSTANT CUBE_1 : cube_t := (
        center_x => 280,
        center_y => 240,
        side_length => 160,
        color => (r => x"FF", g => x"FF", b => x"FF")
    );

    CONSTANT CUBE_2 : cube_t := (
        center_x => 460,
        center_y => 240,
        side_length => 120,
        color => (r => x"00", g => x"FF", b => x"FF")
    );

    CONSTANT CUBE_3 : cube_t := (
        center_x => 500,
        center_y => 240,
        side_length => 100,
        color => (r => x"FF", g => x"00", b => x"00")
    );

    CONSTANT BACKGROUND_COLOR : color_t := (r => x"00", g => x"00", b => x"00");

    SIGNAL pixel_color : color_t := TRANSPARENT;

BEGIN

    x <= to_integer(unsigned(pixel_column));
    y <= to_integer(unsigned(pixel_row));
    
    PROCESS (x, y)
    BEGIN
        pixel_color <= render_scene_pixel(
            x,
            y,
            CUBE_1,
            CUBE_2,
            CUBE_3,
            SCENE_LIGHT,
            BACKGROUND_COLOR
        );
    END PROCESS;

    Red <= pixel_color.r;
    Green <= pixel_color.g;
    Blue <= pixel_color.b;

END ARCHITECTURE behavioral;
