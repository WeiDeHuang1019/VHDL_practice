library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity PingpongOn2Boards_tb is end;
architecture sim of PingpongOn2Boards_tb is
  constant CLK_HZ_TB : integer := 10_000_000;
  signal clk  : std_logic := '0';
  signal rstn : std_logic := '0';

  -- 單線匯流排（弱上拉）
  signal link : std_logic := 'H';

  -- A
  signal A_btn : std_logic := '0';
  signal A_led : std_logic_vector(7 downto 0);
  -- B
  signal B_btn : std_logic := '0';
  signal B_led : std_logic_vector(7 downto 0);
begin
  -- clock
  clk <= not clk after 50 ns;

  -- reset
  process
  begin
    rstn <= '0'; wait for 1 us; rstn <= '1'; wait;
  end process;

  -- UUT A
  U_A: entity work.PingpongOn2Boards
    generic map (CLK_HZ => CLK_HZ_TB, SLOW_DIV_POW2 => 12, PULSE_US => 10)
    port map (i_clk=>clk, i_rst=>rstn, i_btn=>A_btn, io_bus=>link, o_led=>A_led);

  -- UUT B
  U_B: entity work.PingpongOn2Boards
    generic map (CLK_HZ => CLK_HZ_TB, SLOW_DIV_POW2 => 12, PULSE_US => 10)
    port map (i_clk=>clk, i_rst=>rstn, i_btn=>B_btn, io_bus=>link, o_led=>B_led);

  -- Stimulus：A 起跑一次即可啟動輪替
  process
  begin
    wait until rstn='1';
    wait for 0.8 ms;

    -- 按 A 一下（脈衝 ≥1 個 clk 即可）
    A_btn <= '1'; wait for 0.2 ms; A_btn <= '0';

    -- 觀察一段時間（可看到 A→B→A… 的交替）
    wait for 20 ms;
    
    -- 按 A 一下（脈衝 ≥1 個 clk 即可）
    B_btn <= '1'; wait for 0.2 ms; B_btn <= '0';

    assert false report "TB finished." severity note;
    wait;
  end process;
end architecture;
