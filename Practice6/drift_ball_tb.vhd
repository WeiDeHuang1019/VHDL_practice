library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity pingpong_speed_tb is
end pingpong_speed_tb;

architecture sim of pingpong_speed_tb is

    -- DUT Ports
    signal i_clk   : STD_LOGIC := '0';
    signal i_rst   : STD_LOGIC := '0';
    signal i_btn1  : STD_LOGIC := '0';
    signal i_btn2  : STD_LOGIC := '0';
    signal o_led   : STD_LOGIC_VECTOR(7 downto 0);

    constant CLK_PERIOD : time := 10 ns;

    component pingpong_speed
        Port (
            i_clk   : in  STD_LOGIC;
            i_rst   : in  STD_LOGIC;
            i_btn1  : in  STD_LOGIC;
            i_btn2  : in  STD_LOGIC;
            o_led   : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component;

begin

    -- Instantiate DUT
    uut: pingpong_speed
        port map (
            i_clk   => i_clk,
            i_rst   => i_rst,
            i_btn1  => i_btn1,
            i_btn2  => i_btn2,
            o_led   => o_led
        );

    -- Clock Generator
    clk_process: process
    begin
        while true loop
            i_clk <= '0';
            wait for CLK_PERIOD / 2;
            i_clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    -- Stimulus Process
    stim_proc: process
    begin
        -- Reset the system
        i_rst <= '0';
        wait for 100 ns;
        i_rst <= '1';
        wait for 100 ns;

        -- Wait for IDLE 初始狀態穩定，LED應亮在中間 "01000000"
        wait for 800 ns;

        -- 發球：玩家1在正確時機按下 i_btn1
        i_btn1 <= '1';
        wait for 20 ns;
        i_btn1 <= '0';

        -- 模擬 LED 向右跑動，等待到 00000010 時玩家2擊球
        wait until o_led = "00000001";
        wait for 10 ns;
        i_btn2 <= '1';
        wait for 20 ns;
        i_btn2 <= '0';

        -- 模擬 LED 向左跑回來，玩家1錯誤時間擊球（失誤）
        wait for 2 ms;


        -- 等待 FAIL 狀態顯示比分，並自動復位回 IDLE
        wait for 5 ms;


        -- 測試結束
        report "Simulation finished successfully." severity NOTE;
        wait;
    end process;

end sim;
