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
    type SPEED_TYPE is (SLOW, MEDIUM, FAST);

    signal STATE     : STATE_TYPE := IDLE;
    signal SPEED     : SPEED_TYPE := SLOW;

    signal led_reg   : STD_LOGIC_VECTOR(9 downto 0) := "0100000000";  
    signal counter   : STD_LOGIC_VECTOR(25 downto 0) := (others => '0');
    signal lfsr      : STD_LOGIC_VECTOR(7 downto 0) := "00000001";
    signal cntTime   : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal cntPoint1 : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal cntPoint2 : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal failSig   : STD_LOGIC := '0';

    signal ledClk    : STD_LOGIC := '0';    -- LEDpattern觸發訊號
    signal cntClk    : STD_LOGIC := '0';    -- FSM_SPEED、LFSR_random、timer觸發訊號

begin

    --process clockDivider
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter <= (others => '0');
        elsif rising_edge(i_clk) then
            counter <= counter + 1;
            case SPEED is
                when FAST   => ledClk <= counter(21);  -- 最快
                when MEDIUM => ledClk <= counter(23);  -- 中速
                when SLOW   => ledClk <= counter(25);  -- 最慢
            end case;
        end if;
    end process;

    cntClk <= counter(25); 

	--process LFSR_random
	process(cntClk, i_rst)
	begin
		if i_rst = '0' then
			lfsr <= "00000001";
		elsif rising_edge(cntClk) then
			lfsr <= lfsr(6 downto 0) & (lfsr(7) xor lfsr(5));
		end if;
	end process;

	--process FSM_SPEED
	process(cntClk, i_rst)
	begin
		if i_rst = '0' then
			SPEED <= SLOW;
		elsif rising_edge(cntClk) then
			case lfsr(2 downto 0) is
				when "000" | "001" =>
					SPEED <= SLOW;
				when "010" | "011" | "100" =>
					SPEED <= MEDIUM;
				when others =>
					SPEED <= FAST;
			end case;
		end if;
	end process;


    --process FSM_PINGPONG
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            STATE <= IDLE;
        elsif rising_edge(i_clk) then
            case STATE is
                when IDLE =>
                    if (i_btn1 = '1' and led_reg = "0100000000") then
                        STATE <= RIGHT_SHIFT;
                    end if;
                when RIGHT_SHIFT =>
                    if led_reg = "0000000001" then
                        STATE <= FAIL;
                    elsif (led_reg = "0000000010" and i_btn2 = '1') then
                        STATE <= LEFT_SHIFT;
                    elsif (i_btn2 = '1' and led_reg /= "0000000010") then
                        STATE <= FAIL;
                    end if;
                when LEFT_SHIFT =>
                    if led_reg = "1000000000" then
                        STATE <= FAIL;
                    elsif (led_reg = "0100000000" and i_btn1 = '1') then
                        STATE <= RIGHT_SHIFT;
                    elsif (i_btn1 = '1' and led_reg /= "0100000000") then
                        STATE <= FAIL;
                    end if;
                when FAIL =>
                    if cntTime = "0111" then
                        STATE <= IDLE;
                    end if;
            end case;
        end if;
    end process;

    --process LEDpattern
    process(ledClk, i_rst)
    begin
        if i_rst = '0' then
            led_reg <= "0100000000";
        elsif rising_edge(ledClk) then
            case STATE is
                when IDLE =>
                    led_reg <= "0100000000";
                when RIGHT_SHIFT =>
                    led_reg <= '0' & led_reg(9 downto 1);
                when LEFT_SHIFT =>
                    led_reg <= led_reg(8 downto 0) & '0';
                when FAIL =>
                    led_reg(8 downto 5) <= cntPoint1;
                    led_reg(4 downto 1) <= cntPoint2;
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

    --process pointCount
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            cntPoint1 <= (others => '0');
            cntPoint2 <= (others => '0');
        elsif rising_edge(i_clk) then
            case STATE is
                when RIGHT_SHIFT =>
                    if led_reg = "0000000001" then
                        cntPoint1 <= cntPoint1 + 1;
                    elsif (i_btn2 = '1' and led_reg /= "0000000010") then
                        cntPoint1 <= cntPoint1 + 1;
                    end if;
                when LEFT_SHIFT =>
                    if led_reg = "1000000000" then
                        cntPoint2 <= cntPoint2 + 1;
                    elsif (i_btn1 = '1' and led_reg /= "0100000000") then
                        cntPoint2 <= cntPoint2 + 1;
                    end if;
                when others =>
                    null;   
            end case;
        end if;
    end process;

    o_led <= led_reg(8 downto 1);

end Behavioral;
