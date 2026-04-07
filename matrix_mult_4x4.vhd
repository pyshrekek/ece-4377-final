-- ============================================================
-- 4x4 Matrix Multiplier (Fixed-Point)
-- ECE 4377 Final Project
--
-- Format: Q8.8 fixed-point (16-bit signed)
--   - Upper 8 bits: integer part
--   - Lower 8 bits: fractional part
--
-- Usage: C = A * B
--   - All matrices are flattened to 16-element arrays
--   - Element [row][col] is at index (row*4 + col)
--   - Result is available after 2 clock cycles (pipelined)
--
-- Indexing convention:
--   index 0  = row 0, col 0
--   index 1  = row 0, col 1
--   ...
--   index 15 = row 3, col 3
-- ============================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity matrix_mult_4x4 is
    generic (
        DATA_WIDTH : integer := 16;   -- Q8.8 fixed-point
        FRAC_BITS  : integer := 8     -- fractional bits
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        valid_i : in  std_logic;      -- pulse high when A and B are ready

        -- Matrix A (row-major flattened, 16 elements)
        A : in  array16_t;

        -- Matrix B (row-major flattened, 16 elements)
        B : in  array16_t;

        -- Output matrix C = A * B
        C       : out array16_t;
        valid_o : out std_logic       -- high when C is valid
    );
end entity matrix_mult_4x4;

-- ============================================================
-- Package for shared array type
-- (put this in a separate file: matrix_pkg.vhd in real use)
-- ============================================================
-- NOTE: In a real project, move the package to its own file.
-- Included here for standalone convenience.

package matrix_pkg is
    subtype element_t is signed(15 downto 0);
    type array16_t is array(0 to 15) of element_t;
end package;

-- ============================================================
-- Architecture
-- ============================================================
architecture rtl of matrix_mult_4x4 is

    -- Full-precision intermediate: Q16.16 (32-bit) before truncation
    subtype product_t is signed(31 downto 0);
    type products_t is array(0 to 15) of product_t;

    -- Pipeline stage 1: products accumulated
    signal stage1_valid : std_logic;
    signal stage1_C     : products_t;

    -- Pipeline stage 2: truncated to Q8.8
    signal stage2_valid : std_logic;
    signal stage2_C     : array16_t;

begin

    -- ----------------------------------------------------------
    -- Stage 1: Compute dot products (registered)
    -- Each output element C[i][j] = sum over k of A[i][k]*B[k][j]
    -- ----------------------------------------------------------
    process(clk)
        variable row, col, k : integer;
        variable acc : product_t;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                stage1_valid <= '0';
                for idx in 0 to 15 loop
                    stage1_C(idx) <= (others => '0');
                end loop;
            else
                stage1_valid <= valid_i;

                for row in 0 to 3 loop
                    for col in 0 to 3 loop
                        acc := (others => '0');
                        for k in 0 to 3 loop
                            -- Multiply: result is 32-bit Q16.16
                            acc := acc + (A(row*4 + k) * B(k*4 + col));
                        end loop;
                        stage1_C(row*4 + col) <= acc;
                    end loop;
                end loop;
            end if;
        end if;
    end process;

    -- ----------------------------------------------------------
    -- Stage 2: Truncate Q16.16 -> Q8.8 (registered)
    -- Shift right by FRAC_BITS to re-align the binary point.
    -- Saturate on overflow to prevent wraparound artifacts.
    -- ----------------------------------------------------------
    process(clk)
        variable shifted : product_t;
        variable sat_max : product_t;
        variable sat_min : product_t;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                stage2_valid <= '0';
                for idx in 0 to 15 loop
                    stage2_C(idx) <= (others => '0');
                end loop;
            else
                stage2_valid <= stage1_valid;

                -- Saturation limits for signed Q8.8
                --   max =  32767 = 0x7FFF
                --   min = -32768 = 0x8000
                sat_max := to_signed( 32767 * (2**FRAC_BITS), 32);
                sat_min := to_signed(-32768 * (2**FRAC_BITS), 32);

                for idx in 0 to 15 loop
                    shifted := stage1_C(idx);

                    -- Saturate before truncation
                    if shifted > sat_max then
                        stage2_C(idx) <= to_signed(32767, DATA_WIDTH);
                    elsif shifted < sat_min then
                        stage2_C(idx) <= to_signed(-32768, DATA_WIDTH);
                    else
                        -- Arithmetic right shift by FRAC_BITS to re-align
                        stage2_C(idx) <= shifted(DATA_WIDTH + FRAC_BITS - 1
                                                  downto FRAC_BITS);
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- ----------------------------------------------------------
    -- Output assignments
    -- ----------------------------------------------------------
    C       <= stage2_C;
    valid_o <= stage2_valid;

end architecture rtl;
