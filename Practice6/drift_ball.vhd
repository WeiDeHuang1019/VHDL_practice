library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity pingpong_speed is
    Port (
        i_clk   : in  STD_LOGIC;
        i_rst   : in  STD_LOGIC;
        i_btn1  : in  STD_LOGIC;
        i_btn2  : in  STD_LOGIC;
        o_led   : out STD_LOGIC_VECTOR(7 downto 0)
    );
end pingpong_speed;

architecture Behavioral of pingpong_speed is

    type STATE_TYPE is (IDLE, RIGHT_SHIFT, LEFT_SHIFT, FAIL);

    signal STATE     : STATE_TYPE := IDLE;
    signal PRE_STATE     : STATE_TYPE ;

    signal shift_reg   : STD_LOGIC_VECTOR(9 downto 0);  
    signal counter   : STD_LOGIC_VECTOR(25 downto 0);
    signal lfsr      : STD_LOGIC_VECTOR(7 downto 0);
    signal cntTime   : STD_LOGIC_VECTOR(3 downto 0);
    signal cntPoint1 : STD_LOGIC_VECTOR(3 downto 0);
    signal cntPoint2 : STD_LOGIC_VECTOR(3 downto 0);

    signal ledClk    : STD_LOGIC;    -- LEDpattern觸發訊號
    signal cntClk    : STD_LOGIC;    -- LFSR_random、timer觸發訊號

begin

    --process clockDivider
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter <= (others => '0');
        elsif rising_edge(i_clk) then
            counter <= counter + 1;
            if lfsr(1 downto 0) = "00" then
                ledClk <= counter(23);  -- SPEED_FAST 快速
            elsif lfsr(1 downto 0) = "01" then
                ledClk <= counter(24);  -- SPEED_MEDIUM 中速
            elsif lfsr(1 downto 0) = "10" then
                ledClk <= counter(25);  -- SPEED_SLOW 慢速
            else
                ledClk <= ledClk;
            end if;            
        end if;
    end process;
    cntClk <= counter(24);

    --process LFSR_random
	process(cntClk, i_rst)
	begin
		if i_rst = '0' then
			lfsr <= "00000001";
		elsif rising_edge(cntClk) then
			lfsr <= lfsr(6 downto 0) & (lfsr(7) xor lfsr(5));
        else
            lfsr <= lfsr;
		end if;
	end process;

    --process FSM
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            STATE <= IDLE;
        elsif rising_edge(i_clk) then
            PRE_STATE <= STATE ;
            case STATE is
                when IDLE =>
                    if (i_btn1 = '1' and shift_reg = "0100000000") then
                        STATE <= RIGHT_SHIFT;
                    else
                        STATE <= IDLE;
                    end if;
                when RIGHT_SHIFT =>
                    if shift_reg = "0000000001" then
                        STATE <= FAIL;
                    elsif (shift_reg = "0000000010" and i_btn2 = '1') then
                        STATE <= LEFT_SHIFT;
                    elsif (i_btn2 = '1' and shift_reg /= "0000000010") then
                        STATE <= FAIL;
                    else
                        STATE <= RIGHT_SHIFT;
                    end if;
                when LEFT_SHIFT =>
                    if shift_reg = "1000000000" then
                        STATE <= FAIL;
                    elsif (shift_reg = "0100000000" and i_btn1 = '1') then
                        STATE <= RIGHT_SHIFT;
                    elsif (i_btn1 = '1' and shift_reg /= "0100000000") then
                        STATE <= FAIL;
                    else
                        STATE <= LEFT_SHIFT;
                    end if;
                when FAIL =>
                    if cntTime = "0111" then
                        STATE <= IDLE;
                    else
                        STATE <= FAIL;
                    end if;
            end case;
        end if;
    end process;

    --process LED_SHIFT
    process(ledClk, i_rst)
    begin
        if i_rst = '0' then
            shift_reg <= "0100000000";
        elsif rising_edge(ledClk) then
            case STATE is
                when IDLE =>
                    shift_reg <= "0100000000";
                when RIGHT_SHIFT =>
                    shift_reg <= '0' & shift_reg(9 downto 1);
                when LEFT_SHIFT =>
                    shift_reg <= shift_reg(8 downto 0) & '0';
                when FAIL =>
                    shift_reg <= shift_reg; 
            end case;
        end if;
    end process;

    --process LED_output
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            o_led <= "10000000";
        elsif rising_edge(i_clk) then
            case STATE is
                when IDLE =>
                    o_led <= "10000000";
                when RIGHT_SHIFT =>
                    o_led <= shift_reg(8 downto 1);
                when LEFT_SHIFT =>
                    o_led <= shift_reg(8 downto 1);
                when FAIL =>
                    o_led(7 downto 4) <= cntPoint1;
                    o_led(3 downto 0) <= cntPoint2;
            end case;
        end if;
    end process;

    --process timer
    process(cntClk, i_rst)
    begin
        if i_rst = '0' then
            cntTime <= (others => '0');
        elsif rising_edge(cntClk) then
            if STATE = FAIL then
                cntTime <= cntTime + 1;
            else
                cntTime <= (others => '0');
            end if;
        end if;
    end process;

    --process pointCountLeft
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            cntPoint1 <= (others => '0');
        elsif rising_edge(i_clk) then
            case STATE is
                when FAIL =>
                    if (PRE_STATE = RIGHT_SHIFT or PRE_STATE = IDLE) then
                        cntPoint1 <= cntPoint1 + 1;
                    else
                        cntPoint1 <= cntPoint1;
                    end if;
                when others =>
                    cntPoint1 <= cntPoint1;   
            end case;
        end if;
    end process;

    --process pointCountRight
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            cntPoint2 <= (others => '0');
        elsif rising_edge(i_clk) then
            case STATE is
                when FAIL =>
                    if PRE_STATE = LEFT_SHIFT then
                        cntPoint2 <= cntPoint2 + 1;
                    else
                        cntPoint2 <= cntPoint2;
                    end if;
                when others =>
                    cntPoint2 <= cntPoint2;   
            end case;
        end if;
    end process;

end Behavioral;

