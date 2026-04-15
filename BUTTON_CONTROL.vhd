-- ============================================================
-- BUTTON_CONTROL.vhd
-- ECE 4377 Final Project
--
-- Handles user input for zoom and pan controls:
--
--   KEY(0) : move objects right    (debounced, 10 px per press)
--   KEY(1) : move objects left     (debounced, 10 px per press)
--   KEY(2) : move objects down     (debounced, 10 px per press)
--   KEY(3) : move objects up       (debounced, 10 px per press)
--
--   SW(2)  : zoom in  (hold; steps every ~0.5 s via vert_sync)
--   SW(3)  : zoom out (hold; steps every ~0.5 s via vert_sync)
--
-- Zoom levels:
--   0 => 0.25x  1 => 0.5x  2 => 1x (default)  3 => 2x  4 => 4x
--
-- KEY buttons are active-low on DE2-115.
-- Debounce filter: ~20 ms at 50 MHz (1 000 000 cycles).
-- ============================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity button_control is
  generic (
    MOVE_STEP       : integer := 10;         -- pixels per key press
    DEBOUNCE_CYCLES : integer := 1_000_000;  -- ~20 ms at 50 MHz
    ZOOM_FRAMES     : integer := 30          -- vert_sync frames between zoom steps
  );
  port (
    clk         : in  std_logic;
    vert_sync   : in  std_logic;
    key_n       : in  std_logic_vector(3 downto 0);  -- active-low push buttons
    zoom_in_sw  : in  std_logic;                     -- SW(2): hold to zoom in
    zoom_out_sw : in  std_logic;                     -- SW(3): hold to zoom out
    x_offset    : out integer range -320 to 320;
    y_offset    : out integer range -240 to 240;
    zoom_level  : out integer range 0 to 4
  );
end entity button_control;

architecture behavioral of button_control is

  -- ── Debounce counters (one per button) ────────────────────
  type cnt_array_t is array(0 to 3) of integer range 0 to 1_000_001;

  signal db_cnt   : cnt_array_t               := (others => 0);
  signal db_state : std_logic_vector(3 downto 0) := "1111";  -- idle = '1' (active-low)
  signal db_pulse : std_logic_vector(3 downto 0) := "0000";  -- one-cycle press pulse

  -- ── Zoom timer ────────────────────────────────────────────
  signal vsync_prev  : std_logic := '0';
  signal zoom_timer  : integer range 0 to 30 := 0;

  -- ── State registers ───────────────────────────────────────
  signal x_off_r : integer range -320 to 320 := 0;
  signal y_off_r : integer range -240 to 240 := 0;
  signal zoom_r  : integer range 0 to 4      := 2;  -- default: 1x

begin

  x_offset   <= x_off_r;
  y_offset   <= y_off_r;
  zoom_level <= zoom_r;

  -- ── Button debounce + press-pulse generation ──────────────
  debounce_proc : process (clk) is
    variable pulse_v : std_logic_vector(3 downto 0);
  begin
    if rising_edge(clk) then
      pulse_v := "0000";

      for i in 0 to 3 loop
        if key_n(i) = db_state(i) then
          -- Input matches stable state → reset counter
          db_cnt(i) <= 0;
        else
          -- Input differs → count stable-disagreement cycles
          if db_cnt(i) = DEBOUNCE_CYCLES - 1 then
            -- Debounced: accept new state
            db_state(i) <= key_n(i);
            db_cnt(i)   <= 0;
            -- Generate press pulse on falling edge (active-low button pressed)
            if key_n(i) = '0' then
              pulse_v(i) := '1';
            end if;
          else
            db_cnt(i) <= db_cnt(i) + 1;
          end if;
        end if;
      end loop;

      db_pulse <= pulse_v;
    end if;
  end process debounce_proc;

  -- ── Movement + zoom control ───────────────────────────────
  control_proc : process (clk) is
  begin
    if rising_edge(clk) then

      -- ── Directional movement (KEY buttons) ──────────────
      -- KEY(0): move right
      if db_pulse(0) = '1' then
        if x_off_r <= 320 - MOVE_STEP then
          x_off_r <= x_off_r + MOVE_STEP;
        end if;
      end if;

      -- KEY(1): move left
      if db_pulse(1) = '1' then
        if x_off_r >= -320 + MOVE_STEP then
          x_off_r <= x_off_r - MOVE_STEP;
        end if;
      end if;

      -- KEY(2): move down
      if db_pulse(2) = '1' then
        if y_off_r <= 240 - MOVE_STEP then
          y_off_r <= y_off_r + MOVE_STEP;
        end if;
      end if;

      -- KEY(3): move up
      if db_pulse(3) = '1' then
        if y_off_r >= -240 + MOVE_STEP then
          y_off_r <= y_off_r - MOVE_STEP;
        end if;
      end if;

      -- ── Zoom (SW held; rate-limited by vert_sync frames) ─
      vsync_prev <= vert_sync;

      if vert_sync = '1' and vsync_prev = '0' then
        -- Rising edge of vertical sync (~60 Hz)
        if zoom_timer = ZOOM_FRAMES - 1 then
          zoom_timer <= 0;

          -- SW(2) alone: zoom in
          if zoom_in_sw = '1' and zoom_out_sw = '0' then
            if zoom_r < 4 then
              zoom_r <= zoom_r + 1;
            end if;

          -- SW(3) alone: zoom out
          elsif zoom_out_sw = '1' and zoom_in_sw = '0' then
            if zoom_r > 0 then
              zoom_r <= zoom_r - 1;
            end if;
          end if;

        else
          zoom_timer <= zoom_timer + 1;
        end if;
      end if;

    end if;
  end process control_proc;

end architecture behavioral;
