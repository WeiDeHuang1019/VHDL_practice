library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity counter0to9 is
    Port (
        i_clk       : in  STD_LOGIC;
        i_rst       : in  STD_LOGIC;
        o_countUp   : out STD_LOGIC_VECTOR (3 downto 0);
        o_countDown : out STD_LOGIC_VECTOR (3 downto 0)
    );
end counter0to9;

architecture Behavioral of counter0to9 is
    signal counter     : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal slowClk     : STD_LOGIC := '0';
    signal cntUp       : STD_LOGIC_VECTOR (3 downto 0) := "0000";
    signal cntDown     : STD_LOGIC_VECTOR (3 downto 0) := "1001";
begin

    -- Process 1: Clock_divider
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter <= (others => '0');
        elsif rising_edge(i_clk) then
            counter <= counter + 1;
        end if;
    end process;

    slowClk <= counter(25);

    -- Process 2: counterUp
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            cntUp <= "0000";
        elsif rising_edge(slowClk) then
            if cntUp = "1001" then
                cntUp <= "0000";
            else
                cntUp <= cntUp + 1;
            end if;
        end if;
    end process;

    -- Process 3: counterDn
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            cntDown <= "1001";
        elsif rising_edge(slowClk) then
            if cntDown = "0000" then
                cntDown <= "1001";
            else
                cntDown <= cntDown - 1;
            end if;
        end if;
    end process;

    -- 輸出對應
    o_countUp   <= cntUp;
    o_countDown <= cntDown;

end Behavioral;
