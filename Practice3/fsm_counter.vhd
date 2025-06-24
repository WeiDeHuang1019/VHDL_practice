
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity fsm_counter is
    Port (
        i_clk        : in  STD_LOGIC;
        i_rst        : in  STD_LOGIC;
        o_countUp    : out STD_LOGIC_VECTOR(3 downto 0);
        o_countDown  : out STD_LOGIC_VECTOR(3 downto 0)
    );
end fsm_counter;


architecture Behavioral of fsm_counter is
    type STATE_TYPE is (CNT_UP, CNT_DN);
	constant c_max   : STD_LOGIC_VECTOR(3 downto 0) := "1000"; 
	constant c_min   : STD_LOGIC_VECTOR(3 downto 0) := "0001"; 

    signal   STATE   : STATE_TYPE := CNT_UP;
    signal   cntUp   : STD_LOGIC_VECTOR(3 downto 0) := "0000";
    signal   cntDn   : STD_LOGIC_VECTOR(3 downto 0) := "0000";
	signal   slowClk : STD_LOGIC := '0';
    signal   counter : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');

begin
	
	-- process1: FSM
	process(i_clk, i_rst)
	begin
		if i_rst = '0' then
			STATE <= CNT_UP;
		elsif rising_edge(i_clk) then
			case STATE is
				when CNT_UP =>
					if cntUp = c_max then
						STATE <= CNT_DN;
					else
						STATE <= CNT_UP;
					end if;
				when CNT_DN =>
					if cntDn = c_min then
						STATE <= CNT_UP;
					else
						STATE <= CNT_DN;
					end if;
			end case;
		end if;
	end process;

    -- Process 2: Clock_divider
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter <= (others => '0');
        elsif rising_edge(i_clk) then
            counter <= counter + 1;
        end if;
    end process;

	slowClk <= counter(25);
	
	-- process 3: counterUp
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			cntUp <= c_min;
		elsif rising_edge(slowClk) then
			if STATE = CNT_DN then
				cntUp <= "0000";
			elsif STATE = CNT_UP then
				cntUp <= cntUp + 1;
			end if;
		end if;
	end process;
	
	-- process 4: counterDn
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			cntDn <= c_max;
		elsif rising_edge(slowClk) then
			if STATE = CNT_UP then
				cntDn <= "0000";
			elsif STATE = CNT_DN then
				if cntDn = "0000" then
					cntDn <= c_max;
				else
					cntDn <= cntDn - 1;
				end if;
			end if;
		end if;
	end process;
	o_countUp    <= cntUp;
    o_countDown  <= cntDn;
	
end Behavioral;	
	
	
