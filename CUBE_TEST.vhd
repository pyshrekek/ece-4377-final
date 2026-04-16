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
    SIGNAL in_cube1 : BOOLEAN;
    SIGNAL in_cube2 : BOOLEAN;

BEGIN

    x <= to_integer(unsigned(pixel_column));
    y <= to_integer(unsigned(pixel_row));
    
    -- First cube: white, centered at (280, 240)
    in_cube1 <= is_cube_filled(x, y, 280, 240, 160);
    
    -- Second cube: cyan, centered at (460, 240)
    in_cube2 <= is_cube_filled(x, y, 460, 240, 120);

    -- Priority: if in first cube, show white; else if in second cube, show cyan; else black
    Red <= x"FF" WHEN in_cube1 ELSE
           x"00" WHEN in_cube2 ELSE
           x"00";
    Green <= x"FF" WHEN in_cube1 ELSE
             x"FF" WHEN in_cube2 ELSE
             x"00";
    Blue <= x"FF" WHEN in_cube1 ELSE
            x"FF" WHEN in_cube2 ELSE
            x"00";

END ARCHITECTURE behavioral;
