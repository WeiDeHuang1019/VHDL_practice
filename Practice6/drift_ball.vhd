library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity drift_ball is
    Port (
        i_clk : in  STD_LOGIC;
        i_rst : in  STD_LOGIC;
        o_led : out STD_LOGIC_VECTOR(7 downto 0)
    );
end drift_ball;

architecture Behavioral of drift_ball is

    -- 狀態型別
    type STATE_LED_TYPE is (RIGHT_SHIFT, LEFT_SHIFT);
    type STATE_SPEED_TYPE is (SPEED_SLOW, SPEED_MEDIUM, SPEED_FAST);

    -- 狀態暫存器
    signal LED_STATE    : STATE_LED_TYPE := RIGHT_SHIFT;
    signal SPEED_STATE  : STATE_SPEED_TYPE := SPEED_SLOW;

    -- LED pattern
    signal led_reg : STD_LOGIC_VECTOR(7 downto 0) := "10000000";

    -- 除頻器與 ledClk
    signal counter_clk : STD_LOGIC_VECTOR(25 downto 0) := (others => '0');
    signal ledClk, cntClk : STD_LOGIC;

    -- LFSR 隨機數產生器
    signal lfsr_random : STD_LOGIC_VECTOR(7 downto 0) := "00000001";

begin

    -- process clockDivider
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter_clk <= (others => '0');
        elsif rising_edge(i_clk) then
            counter_clk <= counter_clk + 1;
        end if;
        if SPEED_STATE = SPEED_FAST then
            ledClk <= counter_clk(21);
        elsif SPEED_STATE = SPEED_MEDIUM then
            ledClk <= counter_clk(23);
        elsif SPEED_STATE = SPEED_SLOW then
            ledClk <= counter_clk(25);
        end if;
    end process;

    cntClk  <= counter_clk(25);


    -- process FSM_LED
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            LED_STATE <= RIGHT_SHIFT;
        elsif rising_edge(i_clk) then
            case LED_STATE is
                when RIGHT_SHIFT =>
                    if led_reg = "00000001" then
                        LED_STATE <= LEFT_SHIFT;
                    end if;
                when LEFT_SHIFT =>
                    if led_reg = "10000000" then
                        LED_STATE <= RIGHT_SHIFT;
                    end if;
            end case;
        end if;
    end process;

    -- process FSM_SPEED
    process(cntClk, i_rst)
    begin
        if i_rst = '0' then
            SPEED_STATE <= SPEED_SLOW;
        elsif rising_edge(cntClk) then
            case lfsr_random(2 downto 0) is
                when "000" | "001" =>
                    SPEED_STATE <= SPEED_SLOW;
                when "010" | "011" | "100" =>
                    SPEED_STATE <= SPEED_MEDIUM;
                when others =>
                    SPEED_STATE <= SPEED_FAST;
            end case;
            
        end if;
    end process;

    -- process LEDpattern 
    process(ledClk, i_rst)
    begin
        if i_rst = '0' then
            led_reg <= "10000000";
        elsif rising_edge(ledClk) then
            case LED_STATE is
                when RIGHT_SHIFT =>
                    led_reg <= '0' & led_reg(7 downto 1);
                when LEFT_SHIFT =>
                    led_reg <= led_reg(6 downto 0) & '0';
            end case;
        end if;
    end process;

    o_led <= led_reg;


    -- process LFSR_random
    process(cntClk, i_rst)
    begin
        if i_rst = '0' then
            lfsr_random <= "00000001";
        elsif rising_edge(cntClk) then
            lfsr_random <= lfsr_random(6 downto 0) & (lfsr_random(7) xor lfsr_random(5));
        end if;
    end process;

end Behavioral;
