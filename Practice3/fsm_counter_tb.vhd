library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity fsm_counter_tb is
end fsm_counter_tb;

architecture Behavioral of fsm_counter_tb is

    -- 宣告元件
    component fsm_counter
        Port (
            i_clk       : in  STD_LOGIC;
            i_rst       : in  STD_LOGIC;
            o_countUp   : out STD_LOGIC_VECTOR(3 downto 0);
            o_countDown : out STD_LOGIC_VECTOR(3 downto 0)
        );
    end component;

    -- 測試訊號
    signal clk       : STD_LOGIC := '0';
    signal rst       : STD_LOGIC := '1';  -- Active-low reset, 初始為不重置
    signal countUp   : STD_LOGIC_VECTOR(3 downto 0);
    signal countDown : STD_LOGIC_VECTOR(3 downto 0);

    constant CLK_PERIOD : time := 10 ns;

begin

    -- 實體化被測模組
    uut: fsm_counter
        port map (
            i_clk       => clk,
            i_rst       => rst,
            o_countUp   => countUp,
            o_countDown => countDown
        );

    -- 時脈產生器
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    -- 測試流程
    stim_proc: process
    begin
        -- 啟動時先進行 active-low reset
        rst <= '0';  -- 啟動重置
        wait for 20 ns;
        rst <= '1';  -- 釋放重置

        -- 模擬一段時間觀察行為
        wait for 500 ns;

        -- 結束模擬
        wait;
    end process;

end Behavioral;
