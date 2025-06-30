library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity pingpong is
    Port (
        i_clk   : in  STD_LOGIC;
        i_rst   : in  STD_LOGIC;
        i_btn1  : in  STD_LOGIC;
        i_btn2  : in  STD_LOGIC;
        o_LED   : out STD_LOGIC_VECTOR(7 downto 0)
    );
end pingpong;

architecture Behavioral of pingpong is
    type STATE_TYPE is (IDLE, RIGHT_SHIFT, LEFT_SHIFT, FAIL);

    signal STATE     : STATE_TYPE := IDLE;
    signal cntLED    : STD_LOGIC_VECTOR(9 downto 0) := (others => '0');
    signal cntTime   : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal cntPoint1 : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal cntPoint2 : STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
    signal failSig   : STD_LOGIC := '0';
    signal slowClk   : STD_LOGIC := '0';
    signal counter   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
begin

    -- FSM Process
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            STATE <= IDLE;
        elsif rising_edge(i_clk) then
            case STATE is
                when IDLE =>
                    if (i_btn1 = '1' AND cntLED = "0100000000") then
                        STATE <= RIGHT_SHIFT;
                    else
                        STATE <= IDLE;
                    end if;
                when RIGHT_SHIFT =>
                    if cntLED(1) = '1' and i_btn2 = '1' then
                        STATE <= LEFT_SHIFT;
                    elsif failSig = '1' then
                        STATE <= FAIL;
                    end if;
                when LEFT_SHIFT =>
                    if cntLED(8) = '1' and i_btn1 = '1' then
                        STATE <= RIGHT_SHIFT;
                    elsif failSig = '1' then
                        STATE <= FAIL;
                    end if;
                when FAIL =>
                    if cntTime = "1000" then
                        STATE <= IDLE;
                    else
                        STATE <= FAIL;
                    end if;
            end case;
        end if;
    end process;

    -- Clock Divider
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter <= (others => '0');
        elsif rising_edge(i_clk) then
            counter <= counter + 1;
        end if;
    end process;

    slowClk <= counter(4);  -- 模擬用較快的 slowClk

    -- LED Counter
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            cntLED <= (others => '0');
        elsif rising_edge(slowClk) then
            case STATE is
                when IDLE =>
                    cntLED <= "0100000000";
                when RIGHT_SHIFT =>
                    cntLED <= '0' & cntLED(9 downto 1);  -- 手動右移
                when LEFT_SHIFT =>
                    cntLED <= cntLED(8 downto 0) & '0';  -- 手動左移
                when FAIL =>
                    cntLED(8 downto 5) <= cntPoint1;
                    cntLED(4 downto 1) <= cntPoint2;
                when others =>
                    null;
            end case;
        end if;
    end process;

    -- Point Counter
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            cntPoint1 <= (others => '0');
            cntPoint2 <= (others => '0');
        elsif rising_edge(i_clk) then
            if STATE = RIGHT_SHIFT and failSig = '1' then
                cntPoint1 <= cntPoint1 + 1;
            elsif STATE = LEFT_SHIFT and failSig = '1' then
                cntPoint2 <= cntPoint2 + 1;
            end if;
        end if;
    end process;

    -- Timer
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            cntTime <= (others => '0');
        elsif rising_edge(slowClk) then
            if STATE = IDLE or STATE = RIGHT_SHIFT or STATE = LEFT_SHIFT then
                cntTime <= (others => '0');
            elsif STATE = FAIL then
                cntTime <= cntTime + 1;
            end if;
        end if;
    end process;

    -- Fail Detection
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            failSig <= '0';
        elsif rising_edge(i_clk) then
            if STATE = FAIL then
                failSig <= '0';
            elsif STATE = RIGHT_SHIFT then
                if (cntLED(1) /= '1' and i_btn2 = '1') or cntLED = "0000000001" then
                    failSig <= '1';
                end if;
            elsif STATE = LEFT_SHIFT then
                if (cntLED(8) /= '1' and i_btn1 = '1') or cntLED = "1000000000" then
                    failSig <= '1';
                end if;
            end if;
        end if;
    end process;

    -- LED Output
    o_LED <= cntLED(8 downto 1);

end Behavioral;
