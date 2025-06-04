library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity PWM_LED is
    Port (
        i_clk  : in  STD_LOGIC;
        i_rst  : in  STD_LOGIC;
        o_LED  : out STD_LOGIC_VECTOR(3 downto 0)
    );
end PWM_LED;

architecture Behavioral of PWM_LED is
    type STATE_CNT_TYPE is (LED_ON, LED_OFF, LED_WAIT);
    type STATE_PWM_TYPE is (PWM_UP, PWM_DN);
    constant PWM_PERIOD  : UNSIGNED(7 downto 0) := to_unsigned(100, 8);

    signal PWM_CTRL      : UNSIGNED(7 downto 0) := (others => '0');
    signal STATE_CNT     : STATE_CNT_TYPE := LED_ON;
    signal STATE_PRE     : STATE_CNT_TYPE := LED_ON;
    signal STATE_PWM     : STATE_PWM_TYPE := PWM_UP;

    signal cnt1, cnt2    : UNSIGNED(7 downto 0) := (others => '0');
    signal clk_cnt       : STD_LOGIC := '0';
    signal clk_5s        : STD_LOGIC := '0';
    signal counter       : UNSIGNED(31 downto 0) := (others => '0');

begin

    -- Clock divider
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter <= (others => '0');
        elsif rising_edge(i_clk) then
            counter <= counter + 1;
        end if;
    end process;

    clk_cnt <= counter(3);
    clk_pwm <= counter(21);

    -- FSM_CNT with WAIT state
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            STATE_CNT <= LED_OFF;
            STATE_PRE <= LED_OFF;
        elsif rising_edge(i_clk) then
            case STATE_CNT is
                when LED_ON =>
                    if cnt1 = PWM_CTRL then
                        STATE_CNT <= LED_WAIT;
                        STATE_PRE <= LED_ON;
                    end if;
                when LED_OFF =>
                    if cnt2 = (PWM_PERIOD - PWM_CTRL) then
                        STATE_CNT <= LED_WAIT;
                        STATE_PRE <= LED_OFF;
                    end if;
                when LED_WAIT =>
                    if cnt1 = to_unsigned(0, 8) and cnt2 = to_unsigned(0, 8) then
                        if STATE_PRE = LED_ON then
                            STATE_CNT <= LED_OFF;
                        else
                            STATE_CNT <= LED_ON;
                        end if;
                    end if;
                when others =>
                    STATE_CNT <= LED_ON;
            end case;
        end if;
    end process;

    -- FSM_PWM
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            STATE_PWM <= PWM_UP;
        elsif rising_edge(i_clk) then
            case STATE_PWM is
                when PWM_UP =>
                    if PWM_CTRL = PWM_PERIOD then
                        STATE_PWM <= PWM_DN;
                    end if;
                when PWM_DN =>
                    if PWM_CTRL = to_unsigned(0, 8) then
                        STATE_PWM <= PWM_UP;
                    end if;
                when others =>
                    STATE_PWM <= PWM_UP;
            end case;
        end if;
    end process;

    -- counterOn
    process(clk_cnt, i_rst)
    begin
        if i_rst = '0' then
            cnt1 <= (others => '0');
        elsif rising_edge(clk_cnt) then
            if STATE_CNT = LED_OFF or STATE_CNT = LED_WAIT then
                cnt1 <= (others => '0');
            elsif cnt1 = PWM_CTRL then
                cnt1 <= (others => '0');
            elsif STATE_CNT = LED_ON then
                cnt1 <= cnt1 + 1;
            end if;
        end if;
    end process;

    -- counterOff
    process(clk_cnt, i_rst)
    begin
        if i_rst = '0' then
            cnt2 <= (others => '0');
        elsif rising_edge(clk_cnt) then
            if STATE_CNT = LED_ON or STATE_CNT = LED_WAIT then
                cnt2 <= (others => '0');
            elsif cnt2 = (PWM_PERIOD - PWM_CTRL) then
                cnt2 <= (others => '0');
            elsif STATE_CNT = LED_OFF then
                cnt2 <= cnt2 + 1;
            end if;
        end if;
    end process;

    -- counterBrightness
    process(clk_pwm, i_rst)
    begin
        if i_rst = '0' then
            PWM_CTRL <= (others => '0');
        elsif rising_edge(clk_pwm) then
            if STATE_PWM = PWM_UP then
                PWM_CTRL <= PWM_CTRL + 2;
            elsif STATE_PWM = PWM_DN then
                PWM_CTRL <= PWM_CTRL - 2;
            end if;
        end if;
    end process;

    -- LED control
    process(STATE_CNT)
    begin
        if STATE_CNT = LED_ON then
            o_LED <= (others => '1');
        else
            o_LED <= (others => '0');
        end if;
    end process;

end Behavioral;
