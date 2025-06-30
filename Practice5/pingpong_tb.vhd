library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_pingpong is
end tb_pingpong;

architecture sim of tb_pingpong is
    -- DUT component
    component pingpong
        Port (
            i_clk   : in  STD_LOGIC;
            i_rst   : in  STD_LOGIC;
            i_btn1  : in  STD_LOGIC;
            i_btn2  : in  STD_LOGIC;
            o_LED   : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component;

    -- Signals
    signal i_clk   : STD_LOGIC := '0';
    signal i_rst   : STD_LOGIC := '0';
    signal i_btn1  : STD_LOGIC := '0';
    signal i_btn2  : STD_LOGIC := '0';
    signal o_LED   : STD_LOGIC_VECTOR(7 downto 0);

    -- Clock period
    constant clk_period : time := 20 ns;

begin
    -- Instantiate DUT
    uut: pingpong
        port map (
            i_clk  => i_clk,
            i_rst  => i_rst,
            i_btn1 => i_btn1,
            i_btn2 => i_btn2,
            o_LED  => o_LED
        );

    -- Clock generation
    clk_process : process
    begin
        while true loop
            i_clk <= '0';
            wait for clk_period / 2;
            i_clk <= '1';
            wait for clk_period / 2;
        end loop;
    end process;

    -- Stimulus process
    stim_proc: process
    begin
        -- Reset
        i_rst <= '0';
        wait for 40 ns;
        i_rst <= '1';

        -- IDLE → RIGHT_SHIFT
        wait for 300 ns;
        i_btn1 <= '1';  -- MSB side按鈕
        wait for 40 ns;
        i_btn1 <= '0';

        -- RIGHT_SHIFT → LEFT_SHIFT
        wait for 1800 ns;
        i_btn2 <= '1';  -- LSB side按鈕
        wait for 40 ns;
        i_btn2 <= '0';


        -- FAIL → IDLE（等待時間結束）
        wait for 500 ns;

        wait;
    end process;

end sim;
