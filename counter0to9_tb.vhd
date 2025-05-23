library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity counter0to9_tb is
-- Testbench 沒有 ports
end counter0to9_tb;

architecture behavior of counter0to9_tb is

    -- 宣告元件（與原始計數器相同）
    component counter0to9
        Port (
            i_clk       : in  STD_LOGIC;
            i_rst       : in  STD_LOGIC;
            o_countUp   : out STD_LOGIC_VECTOR (3 downto 0);
            o_countDown : out STD_LOGIC_VECTOR (3 downto 0)
        );
    end component;

    -- 測試訊號
    signal i_clk       : STD_LOGIC := '0';
    signal i_rst       : STD_LOGIC := '0';
    signal o_countUp   : STD_LOGIC_VECTOR (3 downto 0);
    signal o_countDown : STD_LOGIC_VECTOR (3 downto 0);

    -- 時脈週期參數
    constant clk_period : time := 10 ns;

begin

    -- 實例化計數器
    uut: counter0to9
        Port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            o_countUp   => o_countUp,
            o_countDown => o_countDown
        );

    -- 時脈產生器
    clk_process : process
    begin
        while true loop
            i_clk <= '0';
            wait for clk_period / 2;
            i_clk <= '1';
            wait for clk_period / 2;
        end loop;
    end process;

    -- 測試流程
    stim_proc: process
    begin
        -- 初始重置
        i_rst <= '1';
        wait for 20 ns;
        i_rst <= '0';

        -- 模擬一段時間讓計數器運作
        wait for 200 ns;

        -- 再次重置
        i_rst <= '1';
        wait for 10 ns;
        i_rst <= '0';

        -- 再觀察一段時間
        wait for 100 ns;

        -- 結束模擬
        wait;
    end process;

end behavior;
