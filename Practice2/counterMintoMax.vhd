library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity counterMintoMax is
    Port (
        i_clk       : in  STD_LOGIC;
        i_rst       : in  STD_LOGIC;
        i_max   	: in  STD_LOGIC_VECTOR (3 downto 0);
		i_min   	: in  STD_LOGIC_VECTOR (3 downto 0);
		o_countUp   : out STD_LOGIC_VECTOR (3 downto 0);
        o_countDown : out STD_LOGIC_VECTOR (3 downto 0)
    );
end counterMintoMax;

architecture Behavioral of counterMintoMax is
    constant MAX_COUNT   : integer := 16665000;		-- cpu時脈為33.33MHz,使產生1sec週期
    signal   counter     : integer range 0 to MAX_COUNT := 0;
    signal   slowClk     : STD_LOGIC := '0';
    signal   cntUp       : STD_LOGIC_VECTOR (3 downto 0) := "0000";
    signal   cntDown     : STD_LOGIC_VECTOR (3 downto 0) := "1001";
begin

    -- Process 1: 計算除頻器的counter
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter <= 0;
        elsif rising_edge(i_clk) then
            if counter = MAX_COUNT then
                counter <= 0;
            else
                counter <= counter + 1;
            end if;
        end if;
    end process;

    -- Process 2: 產生slowClk
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            slowClk <= '0';
        elsif rising_edge(i_clk) then
            if counter = MAX_COUNT then
                slowClk <= not slowClk;
            end if;
        end if;
    end process;

    -- Process 3: 控制 cntUp
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            cntUp <= i_min;
        elsif rising_edge(slowClk) then
            if cntUp = i_max then
                cntUp <= i_min;
            else
                cntUp <= cntUp + 1;
            end if;
        end if;
    end process;

    -- Process 4: 控制 cntDown
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            cntDown <= i_max;
        elsif rising_edge(slowClk) then
            if cntDown = i_min then
                cntDown <= i_max;
            else
                cntDown <= cntDown - 1;
            end if;
        end if;
    end process;

    -- 輸出對應
    o_countUp   <= cntUp;
    o_countDown <= cntDown;

end Behavioral;
