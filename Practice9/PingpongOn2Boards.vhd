library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity PingpongOn2Boards is
    generic (
        CLK_HZ        : integer := 100_000_000;  -- 100 MHz
        SLOW_DIV_POW2 : integer := 23;          -- 慢速位移用的除頻 bit（tb 用 12，真板 23）
        PULSE_US      : integer := 10           -- 送交棒脈衝長度（固定寬度，單位 us）
    );
    port (
        i_clk  : in  std_logic;
        i_rst  : in  std_logic;                 -- 低有效
        i_btn  : in  std_logic;                 -- 起手鍵（IDLE 時按下→自己先跑）
        io_bus : inout std_logic;               -- 單線 open-drain：只拉低、不拉高
        o_led  : out std_logic_vector(7 downto 0)  -- 本板 8 顆 LED
    );
end entity;

architecture rtl of PingpongOn2Boards is
    --------------------------------------------------------------------------
    -- 狀態列舉
    --------------------------------------------------------------------------
    type STATE_T is (IDLE, RIGHT_SHIFT, LEFT_SHIFT, WAITING, FAIL);
    signal STATE : STATE_T := IDLE;

    --------------------------------------------------------------------------
    -- 10-bit 移位暫存 + 慢時鐘
    --------------------------------------------------------------------------
    signal shift_reg : std_logic_vector(9 downto 0) := "0100000000";  -- 顯示取 [8:1]
    signal counter   : unsigned(25 downto 0) := (others => '0');
    signal slowClk   : std_logic;

    --------------------------------------------------------------------------
    -- 匯流排 I/O（open-drain）
    --------------------------------------------------------------------------
    signal drive_low  : std_logic := '0';  -- '1' = 拉低；否則三態
    signal bus_s0     : std_logic := '1';  -- 同步器第 1 級
    signal bus_s1     : std_logic := '1';  -- 同步器第 2 級
    signal bus_s0_lvl : std_logic := '1';  -- 當拍電位：to_X01(bus_s0)
    signal bus_s1_lvl : std_logic := '1';  -- 前拍電位：to_X01(bus_s1)
    signal rx_sig1    : std_logic := '0';  -- 1T 收到脈衝（單拍）
    signal rx_sig2    : std_logic := '0';  -- 2T 收到脈衝（單拍）

    --------------------------------------------------------------------------
    -- 交棒 TX 脈衝產生（固定寬度）
    --------------------------------------------------------------------------
    constant TICKS_PER_US : integer := CLK_HZ / 1_000_000;
    constant PULSE_TICKS  : integer := PULSE_US * TICKS_PER_US;
    constant RX_LONG_THRESH_TICKS : integer := (3 * PULSE_TICKS) / 2;  -- 1.5T

    signal tx_T    : integer range 0 to 2 := 1;                -- 1T 長度 = PULSE_TICKS
    signal tx_sig1 : std_logic := '0';                          -- 觸發 TX → 1T
    signal tx_sig2 : std_logic := '0';                          -- 觸發 TX → 2T
    signal tx_cnt  : integer range 0 to 2*PULSE_TICKS := 0;     -- TX 計數

    -- RX 長度量測
    signal rx_cnt        : integer range 0 to 2*PULSE_TICKS := 0;  -- >=1T 視為 2T
    signal rx_start_tick : std_logic := '0';

    signal failtest : std_logic := '0';
    signal point    : integer range 0 to 127 := 0;
    signal cntTime  : unsigned(2 downto 0) := (others => '0');
begin
    --------------------------------------------------------------------------
    -- Open-drain：只拉低、不拉高；其餘時間交給上拉
    --------------------------------------------------------------------------
    io_bus <= '0' when drive_low = '1' else 'Z';

    --------------------------------------------------------------------------
    -- 匯流排同步（每個 process 只控一個暫存）
    --------------------------------------------------------------------------
    -- bus_s0
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            bus_s0 <= io_bus;
        end if;
    end process;

    -- bus_s1
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            bus_s1 <= bus_s0;
        end if;
    end process;

    -- bus_s0_lvl
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            bus_s0_lvl <= to_X01(bus_s0);  -- 'H'→'1'、'Z'/'U'→'X'
        end if;
    end process;

    -- bus_s1_lvl
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            bus_s1_lvl <= to_X01(bus_s1);  -- 一拍前的正規化電位
        end if;
    end process;

    --------------------------------------------------------------------------
    -- RX：以正規化後之 1→0 / 0→1 邊緣做量測（TX 期間不接收）
    --------------------------------------------------------------------------
    -- rx_start_tick：量測期間為 '1'，結束時清為 '0'
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if ((drive_low = '0' and bus_s1_lvl = '1' and bus_s0_lvl = '0') or rx_start_tick = '1') then
                if (drive_low = '0' and bus_s1_lvl = '0' and bus_s0_lvl = '1') then
                    rx_start_tick <= '0';  -- 低→高：結束
                else
                    rx_start_tick <= '1';  -- 量測中
                end if;
            else
                rx_start_tick <= '0';
            end if;
        end if;
    end process;

    -- rx_cnt：低電位持續時間
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if ((drive_low = '0' and bus_s1_lvl = '1' and bus_s0_lvl = '0') or rx_start_tick = '1') then
                if (drive_low = '0' and bus_s1_lvl = '0' and bus_s0_lvl = '1') then
                    rx_cnt <= rx_cnt;      -- 結束當拍保持，下一拍外層會清 0
                else
                    rx_cnt <= rx_cnt + 1;
                end if;
            else
                rx_cnt <= 0;
            end if;
        end if;
    end process;

    -- rx_sig1：結束當拍且 rx_cnt <= 1T 時打一拍
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if (((drive_low = '0' and bus_s1_lvl = '1' and bus_s0_lvl = '0') or rx_start_tick = '1') and
                 (drive_low = '0' and bus_s1_lvl = '0' and bus_s0_lvl = '1')) then
                if (rx_cnt > RX_LONG_THRESH_TICKS) then
                    rx_sig1 <= '0';
                else
                    rx_sig1 <= '1';
                end if;
            else
                rx_sig1 <= '0';
            end if;
        end if;
    end process;

    -- rx_sig2：結束當拍且 rx_cnt > 1T 時打一拍
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if (((drive_low = '0' and bus_s1_lvl = '1' and bus_s0_lvl = '0') or rx_start_tick = '1') and
                 (drive_low = '0' and bus_s1_lvl = '0' and bus_s0_lvl = '1')) then
                if (rx_cnt > RX_LONG_THRESH_TICKS) then
                    rx_sig2 <= '1';
                else
                    rx_sig2 <= '0';
                end if;
            else
                rx_sig2 <= '0';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- 慢時鐘（跑馬燈節拍）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter <= (others => '0');
        elsif rising_edge(i_clk) then
            counter <= counter + 1;
        end if;
    end process;

    slowClk <= std_logic(counter(SLOW_DIV_POW2));  -- 取某 bit 當慢節拍

    --------------------------------------------------------------------------
    -- [P1] 只控制 STATE（沿用你的轉移規則）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            STATE <= IDLE;
        elsif rising_edge(i_clk) then
            case STATE is
                when IDLE =>
                    if i_btn = '1' then
                        STATE <= RIGHT_SHIFT;
                    elsif (rx_sig1 = '1') then
                        STATE <= WAITING;     -- 對面宣告佔用 → 我等待
                    else
                        STATE <= IDLE;
                    end if;

                when RIGHT_SHIFT =>
                    if (shift_reg = "0000000001") then
                        STATE <= WAITING;     -- 右牆反彈（依你原先邏輯）
                    else
                        STATE <= RIGHT_SHIFT;
                    end if;

                when LEFT_SHIFT =>
                    if (shift_reg = "0100000000" and i_btn = '1') then
                        STATE <= RIGHT_SHIFT; -- 成功擊球
                    elsif (tx_sig2 = '1') then
                        STATE <= FAIL;
                    else
                        STATE <= LEFT_SHIFT;
                    end if;

                when WAITING =>
                    if (rx_sig1 = '1') then
                        STATE <= LEFT_SHIFT;  -- 收到交棒 → 我開始跑
                    elsif (rx_sig2 = '1') then
                        STATE <= FAIL;
                    else
                        STATE <= WAITING;
                    end if;

                when FAIL =>
                    if cntTime = "111" then
                        STATE <= IDLE;
                    else
                        STATE <= FAIL;
                    end if;
            end case;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P2a] 只控制 tx_sig1（單拍）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            tx_sig1 <= '0';
        elsif rising_edge(i_clk) then
            tx_sig1 <= '0';
            case STATE is
                when IDLE =>
                    if (i_btn = '1') then
                        tx_sig1 <= '1';       -- 起跑
                    end if;
                when RIGHT_SHIFT =>
                    if (shift_reg = "0000000010") then
                        tx_sig1 <= '1';       -- 右端
                    end if;
                when others =>
                    null;
            end case;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P2b] 只控制 tx_sig2（單拍）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            tx_sig2 <= '0';
        elsif rising_edge(i_clk) then
            tx_sig2 <= '0';
            case STATE is
                when LEFT_SHIFT =>
                    if ((shift_reg = "0100000000" and i_btn /= '1') or shift_reg = "1000000000") then
                        tx_sig2 <= '1';       -- 失敗條件
                    end if;
                when others =>
                    null;
            end case;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P3a] 只控制 drive_low（TX 脈衝）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            drive_low <= '0';
        elsif rising_edge(i_clk) then
            if drive_low = '0' then
                if (tx_sig1 = '1' or tx_sig2 = '1') then
                    drive_low <= '1';         -- 開始拉低
                else
                    drive_low <= '0';
                end if;
            else
                if tx_cnt >= (tx_T * PULSE_TICKS) - 1 then
                    drive_low <= '0';         -- 放手
                else
                    drive_low <= '1';
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P3b] 只控制 tx_cnt
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            tx_cnt <= 0;
        elsif rising_edge(i_clk) then
            if drive_low = '0' then
                if (tx_sig1 = '1' or tx_sig2 = '1') then
                    tx_cnt <= 0;              -- 開始計時
                else
                    tx_cnt <= tx_cnt;         -- 保持
                end if;
            else
                if tx_cnt >= (tx_T * PULSE_TICKS) - 1 then
                    tx_cnt <= 0;              -- 結束
                else
                    tx_cnt <= tx_cnt + 1;     -- 遞增
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P3c] 只控制 tx_T
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            null;                              -- 保持宣告初值 1
        elsif rising_edge(i_clk) then
            if drive_low = '0' then
                if tx_sig1 = '1' then
                    tx_T <= 1;
                elsif tx_sig2 = '1' then
                    tx_T <= 2;
                else
                    tx_T <= tx_T;
                end if;
            else
                if tx_cnt >= (tx_T * PULSE_TICKS) - 1 then
                    tx_T <= 0;                 -- 結束時清 0（沿用你的作法）
                else
                    tx_T <= tx_T;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P4] 只控制 shift_reg（慢時鐘推動）
    --------------------------------------------------------------------------
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            shift_reg <= "0100000000";         -- 左端預設
        elsif rising_edge(slowClk) then
            case STATE is
                when IDLE        => shift_reg <= "1000000000";
                when RIGHT_SHIFT => shift_reg <= '0' & shift_reg(9 downto 1);
                when LEFT_SHIFT  => shift_reg <= shift_reg(8 downto 0) & '0';
                when WAITING     => shift_reg <= "0000000001";  -- 等待時右端待命
                when FAIL        => shift_reg(8 downto 1) <= std_logic_vector(to_unsigned(point, 8));
            end case;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P5] 只控制 o_led
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            o_led <= (others => '0');
        elsif rising_edge(i_clk) then
            o_led <= shift_reg(8 downto 1);
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P6] 計算分數
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            point <= 0;
        elsif rising_edge(i_clk) then
            if (STATE = WAITING and rx_sig2 = '1') then
                point <= point + 1;
            else
                point <= point;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P7] 計時器
    --------------------------------------------------------------------------
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            cntTime <= (others => '0');
        elsif rising_edge(slowClk) then
            if STATE = FAIL then
                cntTime <= cntTime + 1;
            else
                cntTime <= (others => '0');
            end if;
        end if;
    end process;

end architecture;
