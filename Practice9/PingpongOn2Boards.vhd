library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity PingpongOn2Boards is
    generic (
        CLK_HZ        : integer := 100_000_000;  -- 100 MHz
        SLOW_DIV_POW2 : integer := 23;          -- 慢速位移用的除頻 bit（tb 用 12，真板 23）
        PULSE_US      : integer := 10           -- 脈衝長度（固定寬度，單位 us）
    );
    port (
        i_clk  : in  std_logic;
        i_rst  : in  std_logic;                 -- low-active
        i_btn  : in  std_logic;                 
        io_bus : inout std_logic;               -- 單線 open-drain：只拉低、不拉高
        o_led  : out std_logic_vector(7 downto 0)  -- 本板 8 顆 LED
    );
end entity;

architecture rtl of PingpongOn2Boards is

    -- TX 脈衝產生寬度常數
    constant TICKS_PER_US : integer := CLK_HZ / 1_000_000;    -- 每微秒拍數
    constant PULSE_TICKS  : integer := PULSE_US * TICKS_PER_US;  -- 1T的長度,映射到tx_T
    constant RX_LONG_THRESH_TICKS : integer := (3 * PULSE_TICKS) / 2;  -- 給RX使用的判斷依據, 用1.5T判斷而非1T, 避免邊緣判斷錯誤

    -- 狀態列舉
    type STATE_T is (IDLE, RIGHT_SHIFT, LEFT_SHIFT, WAITING, FAIL);
    signal STATE : STATE_T := IDLE;

    -- 慢時脈除頻
    signal counter   : unsigned(25 downto 0) := (others => '0');
    signal slowClk   : std_logic;

    -- 同步器（open-drain）
    signal bus_s0     : std_logic := '1';  -- 同步器第 1 級
    signal bus_s1     : std_logic := '1';  -- 同步器第 2 級
    signal bus_s0_lvl : std_logic := '1';  -- 當拍電位：to_X01(bus_s0), 正規化後的bus_s0
    signal bus_s1_lvl : std_logic := '1';  -- 前拍電位：to_X01(bus_s1), 正規化後的bus_s1

    -- TX
    signal tx_T    : integer range 0 to 2 := 1;                 -- 決定TX訊號長度
    signal tx_cnt  : integer range 0 to 2*PULSE_TICKS := 0;     -- TX計算器(計算TX訊號為sig1或sig2)
    signal tx_sig1 : std_logic := '0';                          -- 觸發 TX 短訊號 
    signal tx_sig2 : std_logic := '0';                          -- 觸發 TX 長訊號 
    signal drive_low  : std_logic := '0';  -- Output Enable ('1'時拉低IObus；否則三態)

    -- RX 
    signal rx_cnt        : integer range 0 to 2*PULSE_TICKS := 0;  -- RX計算器(計算RX訊號為sig1或sig2)
    signal rx_start_tick : std_logic := '0';    -- 開始計算rx訊號長度
    signal rx_sig1    : std_logic := '0';  -- 1T 收到脈衝（單拍）
    signal rx_sig2    : std_logic := '0';  -- 2T 收到脈衝（單拍）

    -- 其他signal
    signal shift_reg : std_logic_vector(9 downto 0) := "0100000000";  -- 移位暫存器
    signal server   : std_logic := '1';                               -- 球權 ('1'時進攻方, '0'時防守方)
    signal point    : integer range 0 to 127 := 0;                    -- 分數
    signal cntTime  : unsigned(2 downto 0) := (others => '0');        -- 計時器

begin
    --------------------------------------------------------------------------
    -- io_bus: Open-drain, 發送訊號時拉低, 其餘時間高阻抗
    --------------------------------------------------------------------------
    io_bus <= '0' when drive_low = '1' else 'Z';

    --------------------------------------------------------------------------
    -- 雙級同步器: 防止bus亞穩態、取樣上下緣
    --------------------------------------------------------------------------
    -- process: bus_s0
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            bus_s0 <= io_bus;
        end if;
    end process;

    -- process: bus_s1
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            bus_s1 <= bus_s0;
        end if;
    end process;

    -- process: bus_s0_lvl
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            bus_s0_lvl <= to_X01(bus_s0);  -- 'H'→'1'、'Z'/'U'→'X'
        end if;
    end process;

    -- process: bus_s1_lvl
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            bus_s1_lvl <= to_X01(bus_s1);  -- 一拍前的正規化電位
        end if;
    end process;

    --------------------------------------------------------------------------
    -- 除頻器: 產生慢速時脈
    --------------------------------------------------------------------------
    -- process: slow_clk
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
    -- RX：控制rx_start_tick, rx_cnt, rx_sig1, rx_sig2
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
            if (rx_start_tick = '1') then
                rx_cnt <= rx_cnt + 1;
            else
                rx_cnt <= 0;
            end if;
        end if;
    end process;

    -- rx_sig1：結束當拍且 rx_cnt <= 1.5T 時
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if (drive_low = '0' and bus_s1_lvl = '0' and bus_s0_lvl = '1') then
                if ((rx_cnt < RX_LONG_THRESH_TICKS) and (rx_cnt > 0)) then
                    rx_sig1 <= '1';
                else
                    rx_sig1 <= '0';
                end if;
            else
                rx_sig1 <= '0';
            end if;
        end if;
    end process;

    -- rx_sig2：結束當拍且 rx_cnt > 1.5T 時
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if (drive_low = '0' and bus_s1_lvl = '0' and bus_s0_lvl = '1') then
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
    -- TX：控制tx_sig1, tx_sig2, tx_T, tx_cnt
    --------------------------------------------------------------------------
    -- process: tx_sig1
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            tx_sig1 <= '0';
        elsif rising_edge(i_clk) then
            tx_sig1 <= '0';
            case STATE is
                when IDLE =>
                    if (i_btn = '1' and server = '1') then
                        tx_sig1 <= '1';       -- 起跑
                    end if;
                when LEFT_SHIFT =>
                    if (shift_reg = "0100000000" and i_btn = '1') then
                        tx_sig1 <= '1';       -- 成功擊球 → 發一個短訊號讓對方server <='0'
                    end if;
                when RIGHT_SHIFT =>
                    if (shift_reg = "0000000001") then
                        tx_sig1 <= '1';       -- 右端
                    end if;
                when others =>
                    null;
            end case;
        end if;
    end process;

    -- process: tx_sig2
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            tx_sig2 <= '0';
        elsif rising_edge(i_clk) then
            tx_sig2 <= '0';
            case STATE is
                when LEFT_SHIFT =>
                    if ((shift_reg /= "0100000000" and i_btn = '1') or shift_reg = "1000000000") then
                        tx_sig2 <= '1';       -- 失敗條件: 提早打擊與過頭(球於本板)
                    end if;
                when WAITING =>
                    if (i_btn = '1' and server = '0') then
                        tx_sig2 <= '1';       -- 失敗條件: 提早打擊(球於對面板)
                    end if;
                when others =>
                    null;
            end case;
        end if;
    end process;

    -- process: drive_low（TX 脈衝）
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

    -- process: tx_cnt
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            tx_cnt <= 0;
        elsif rising_edge(i_clk) then
            if drive_low = '0' then
                tx_cnt <= 0;              -- 保持'0'
            else
                if tx_cnt >= (tx_T * PULSE_TICKS) - 1 then
                    tx_cnt <= 0;              -- 結束
                else
                    tx_cnt <= tx_cnt + 1;     -- 遞增
                end if;
            end if;
        end if;
    end process;

    -- process: tx_T
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
    -- FSM: 控制STATE變化
    --------------------------------------------------------------------------
    -- process: STATE
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            STATE <= IDLE;
        elsif rising_edge(i_clk) then
            case STATE is
                when IDLE =>
                    if (i_btn = '1' and server = '1'and shift_reg = "0100000000") then
                        STATE <= RIGHT_SHIFT;
                    elsif (rx_sig1 = '1') then
                        STATE <= WAITING;     -- 對面宣告佔用 → 我等待
                    else
                        STATE <= IDLE;
                    end if;

                when RIGHT_SHIFT =>
                    if (shift_reg = "0000000001") then
                        STATE <= WAITING;   
                    elsif (rx_sig2 = '1') then
                        STATE <= FAIL;  
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
                    if (server = '0' and rx_sig1 = '1') then
                        STATE <= LEFT_SHIFT;  -- 防守方時收到交棒 → 我開始跑
                    elsif (rx_sig2 = '1') then
                        STATE <= FAIL;
                    elsif (tx_sig2 = '1') then
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
    -- 其他Signal控制: shift_reg, server, point, cntTime
    --------------------------------------------------------------------------
    -- process: shift_reg
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            shift_reg <= "0100000000";         -- 左端預設
        elsif rising_edge(slowClk) then
            case STATE is
                when IDLE => 
                    if (server = '1' ) then
                        shift_reg <= "0100000000";
                    else
                        shift_reg <= "0000000000";
                    end if;
                when RIGHT_SHIFT => shift_reg <= '0' & shift_reg(9 downto 1);
                when LEFT_SHIFT  => shift_reg <= shift_reg(8 downto 0) & '0';
                when WAITING     => shift_reg <= "0000000001";  -- 等待時右端待命
                when FAIL        => shift_reg(8 downto 1) <= std_logic_vector(to_unsigned(point, 8));
            end case;
        end if;
    end process;

    -- process: server
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            server <= '1';
        elsif rising_edge(i_clk) then
            if (STATE = IDLE and rx_sig1 = '1') then
                server <= '0';            -- 對方發球 → server <= '0' 此輪變防守方
            elsif (STATE = RIGHT_SHIFT) then
                server <= '1';            -- 我成功回擊 → server <= '1' 此輪變進攻方
            elsif (STATE = WAITING and server = '1' and rx_sig1 = '1') then
                server <= '0';            -- 對方成功回擊 → server <= '0' 此輪變防守方
            elsif (STATE = WAITING and rx_sig2 = '1') then
                server <= '1';            -- 我得分 → server <= '1' 下輪為進攻方(發球權)
            elsif (STATE = LEFT_SHIFT and tx_sig2 = '1') then
                server <= '0';            -- 我失誤 → server <= '0' 下輪為防守方
            else
                server <= server;
            end if;
        end if;
    end process;

    -- process: point
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            point <= 0;
        elsif rising_edge(i_clk) then
            if ( rx_sig2 = '1') then
                point <= point + 1;
            else
                point <= point;
            end if;
        end if;
    end process;

    -- process: cntTime
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

    --------------------------------------------------------------------------
    --  輸出LED: 負責輸出o_led訊號
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            o_led <= (others => '0');
        elsif rising_edge(i_clk) then
            o_led <= shift_reg(8 downto 1);
        end if;
    end process;

end architecture;
