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
    type STATE_SPEED_TYPE is (SPEED_SLOW, SPEED_FAST);

    -- 狀態暫存器
    signal LED_STATE    : STATE_LED_TYPE := RIGHT_SHIFT;
    signal SPEED_STATE  : STATE_SPEED_TYPE := SPEED_SLOW;

    -- LED pattern
    signal led_reg : STD_LOGIC_VECTOR(7 downto 0) := "00000001";

    -- 除頻器與 slowClk
    signal counter_clk : STD_LOGIC_VECTOR(24 downto 0) := (others => '0');
    signal slowClk, cntClk : STD_LOGIC;

    -- 切換速度的計數器
    signal counter_speed : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');

begin

    -- 除頻器產生 slowClk 與 cntClk
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter_clk <= (others => '0');
        elsif rising_edge(i_clk) then
            counter_clk <= counter_clk + 1;
        end if;
    end process;

    cntClk  <= counter_clk(24);
    with SPEED_STATE select
    slowClk <= counter_clk(21) when SPEED_FAST,
               counter_clk(24) when SPEED_SLOW,
               counter_clk(24) when others;
    
	--for simulation--------------------------
/* 	cntClk  <= counter_clk(12);  -- 每約 40 us
    with SPEED_STATE select
    slowClk <= counter_clk(8)  when SPEED_FAST,
               counter_clk(10) when SPEED_SLOW,
               counter_clk(10) when others; */
	------------------------------------------

    ----------------------------------------------------------------
    -- 1. FSM_LED：根據目前 LED 位置，改變 LED_STATE（不控制 LED）
    ----------------------------------------------------------------
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

    ----------------------------------------------------------------
    -- 2. FSM_SPEED：三角波變速切換（兩段速度）
    ----------------------------------------------------------------
    process(cntClk, i_rst)
    begin
        if i_rst = '0' then
            SPEED_STATE <= SPEED_SLOW;
        elsif rising_edge(cntClk) then
            if counter_speed = "0011" then
                if SPEED_STATE = SPEED_SLOW then
                    SPEED_STATE <= SPEED_FAST;
                else
                    SPEED_STATE <= SPEED_SLOW;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- 3. counter_speed：控制變速切換的 delay 計數
    ----------------------------------------------------------------
    process(cntClk, i_rst)
    begin
        if i_rst = '0' then
            counter_speed <= (others => '0');
        elsif rising_edge(cntClk) then
            if counter_speed = "0011" then
                counter_speed <= (others => '0');
            else
                counter_speed <= counter_speed + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- 4. LED pattern 控制（用 slowClk 控制，依 LED_STATE 移動）
    ----------------------------------------------------------------
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            led_reg <= "10000000";
        elsif rising_edge(slowClk) then
            case LED_STATE is
                when RIGHT_SHIFT =>
                    led_reg <= '0' & led_reg(7 downto 1);
                when LEFT_SHIFT =>
                    led_reg <= led_reg(6 downto 0) & '0';
            end case;
        end if;
    end process;

    ----------------------------------------------------------------
    -- LED 輸出
    ----------------------------------------------------------------
    o_led <= led_reg;

end Behavioral;
