LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE work.GRAPHICS_TEST_UTILS.ALL;

ENTITY CUBE_TEST IS
    PORT (
        pixel_row : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        pixel_column : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
        vert_sync : IN STD_LOGIC;
        Red : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        Green : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        Blue : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
END ENTITY CUBE_TEST;

ARCHITECTURE behavioral OF CUBE_TEST IS

    SIGNAL x : INTEGER RANGE 0 TO 639;
    SIGNAL y : INTEGER RANGE 0 TO 639;
    SIGNAL on_cube : BOOLEAN;

BEGIN

    x <= to_integer(unsigned(pixel_column));
    y <= to_integer(unsigned(pixel_row));
    on_cube <= is_on_cube(x, y, 320, 240, 180);

    Red <= x"FF" WHEN on_cube ELSE
        x"00";
    Green <= x"FF" WHEN on_cube ELSE
        x"00";
    Blue <= x"FF" WHEN on_cube ELSE
        x"00";

END ARCHITECTURE behavioral;
