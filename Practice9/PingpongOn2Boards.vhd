library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;  -- 用向量做加減/比較（unsigned 解讀）

entity PingpongOn2Boards is
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
    -- 跑馬燈暫存 & 慢拍（用分頻計數器的一個 bit；無跨時脈網）
    --------------------------------------------------------------------------
    signal shift_reg : std_logic_vector(9 downto 0) := "0100000000";  -- 顯示取 [8:1]
    signal counter   : std_logic_vector(25 downto 0) := (others => '0');
    signal slowClk   : std_logic;

    --------------------------------------------------------------------------
    -- 匯流排 I/O（open-drain）
    --------------------------------------------------------------------------
    signal drive_low  : std_logic := '0';  -- '1' = 拉低；否則三態
    signal bus_s0     : std_logic := '1';
    signal bus_s1     : std_logic := '1';
    signal bus_s0_lvl : std_logic := '1';
    signal bus_s1_lvl : std_logic := '1';
    signal rx_sig1    : std_logic := '0';  -- 短訊號（單拍）
    signal rx_sig2    : std_logic := '0';  -- 長訊號（單拍）

    -- TX 觸發脈衝（單拍）
    signal tx_sig1    : std_logic := '0';
    signal tx_sig2    : std_logic := '0';

    --------------------------------------------------------------------------
    -- 寫死的脈衝/門檻（以 10MHz 時脈規劃：1T=100clk、2T=200clk、閾值=150clk）
    -- 全用 16-bit std_logic_vector，配合 STD_LOGIC_UNSIGNED 做運算
    --------------------------------------------------------------------------
   -- 100 MHz: 1T = 1000 clk, 2T = 2000 clk, 閾值=1.5T=1500 clk
    constant C_1T   : std_logic_vector(15 downto 0) := "0000001111101000"; -- 1000 (0x03E8)
    constant C_2T   : std_logic_vector(15 downto 0) := "0000011111010000"; -- 2000 (0x07D0)
    constant C_RXTH : std_logic_vector(15 downto 0) := "0000010111011100"; -- 1500 (0x05DC)
    constant C_ONE16  : std_logic_vector(15 downto 0) := "0000000000000001";
    constant C_ZERO16 : std_logic_vector(15 downto 0) := "0000000000000000";

    -- TX 計數/目標（≤32bit 要求下用 16bit 已綽綽有餘）
    signal tx_target  : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_cnt     : std_logic_vector(15 downto 0) := (others => '0');

    -- RX 低電位持續時間
    signal rx_cnt     : std_logic_vector(15 downto 0) := (others => '0');
    signal rx_start   : std_logic := '0';

    -- 其他
    signal server     : std_logic := '1';                         -- 球權
    signal point      : std_logic_vector(7 downto 0) := (others => '0');  -- 0..127
    signal cntTime    : std_logic_vector(2 downto 0) := (others => '0');
begin
    --------------------------------------------------------------------------
    -- Open-drain：只拉低、不拉高；其餘時間交給上拉
    --------------------------------------------------------------------------
    io_bus <= '0' when drive_low = '1' else 'Z';

    --------------------------------------------------------------------------
    -- 匯流排同步 + 正規化
    --------------------------------------------------------------------------
    process(i_clk) begin if rising_edge(i_clk) then bus_s0 <= io_bus; end if; end process;
    process(i_clk) begin if rising_edge(i_clk) then bus_s1 <= bus_s0; end if; end process;
    process(i_clk) begin if rising_edge(i_clk) then bus_s0_lvl <= to_X01(bus_s0); end if; end process;
    process(i_clk) begin if rising_edge(i_clk) then bus_s1_lvl <= to_X01(bus_s1); end if; end process;

    --------------------------------------------------------------------------
    -- RX：以 1→0 / 0→1 邊緣量測（TX 期間不接收），用向量計數
    --------------------------------------------------------------------------
    -- 起訖旗標
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if ((drive_low='0' and bus_s1_lvl='1' and bus_s0_lvl='0') or rx_start='1') then
                if (drive_low='0' and bus_s1_lvl='0' and bus_s0_lvl='1') then
                    rx_start <= '0';  -- 低→高：結束
                else
                    rx_start <= '1';  -- 量測中
                end if;
            else
                rx_start <= '0';
            end if;
        end if;
    end process;

    -- 持續時間計數（std_logic_vector + STD_LOGIC_UNSIGNED）
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if rx_start='1' then
                rx_cnt <= rx_cnt + 1;
            else
                rx_cnt <= C_ZERO16;
            end if;
        end if;
    end process;

    -- 分類：短（結束當拍且 0 < rx_cnt < 1.5T）
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if (drive_low='0' and bus_s1_lvl='0' and bus_s0_lvl='1') then
                if (rx_cnt /= C_ZERO16 and rx_cnt < C_RXTH) then
                    rx_sig1 <= '1';
                else
                    rx_sig1 <= '0';
                end if;
            else
                rx_sig1 <= '0';
            end if;
        end if;
    end process;

    -- 分類：長（結束當拍且 rx_cnt >= 1.5T）
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if (drive_low='0' and bus_s1_lvl='0' and bus_s0_lvl='1') then
                if (rx_cnt >= C_RXTH) then
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
    -- 慢時鐘（跑馬燈節拍）：固定取 counter(12)
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst='0' then
            counter <= (others => '0');
        elsif rising_edge(i_clk) then
            counter <= counter + 1;
        end if;
    end process;

    slowClk <= counter(23);  -- 寫死分頻位元

    --------------------------------------------------------------------------
    -- [P1] 只控制 STATE（沿用你的轉移規則）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst='0' then
            STATE <= IDLE;
        elsif rising_edge(i_clk) then
            case STATE is
                when IDLE =>
                    if (i_btn='1' and server='1' and shift_reg = "0100000000") then
                        STATE <= RIGHT_SHIFT;
                    elsif (rx_sig1='1') then
                        STATE <= WAITING;
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
                    if (shift_reg="0100000000" and i_btn='1') then
                        STATE <= RIGHT_SHIFT; -- 成功擊球
                    elsif (tx_sig2='1') then
                        STATE <= FAIL;
                    else
                        STATE <= LEFT_SHIFT;
                    end if;

                when WAITING =>
                    if (server='0' and rx_sig1='1') then
                        STATE <= LEFT_SHIFT;    -- 防守方時收到交棒 → 我開始跑
                    elsif (rx_sig2='1') then
                        STATE <= FAIL;
					elsif (tx_sig2 = '1') then
                        STATE <= FAIL;
                    else
                        STATE <= WAITING;
                    end if;

                when FAIL =>
                    if (cntTime="111") then
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
        if i_rst='0' then
            tx_sig1 <= '0';
        elsif rising_edge(i_clk) then
            tx_sig1 <= '0';
			if rx_start = '0' then
				case STATE is
					when IDLE =>
						if (i_btn='1' and server='1') then
							tx_sig1 <= '1';       -- 起跑
						end if;
					when LEFT_SHIFT =>
						if (shift_reg="0100000000" and i_btn='1') then
							tx_sig1 <= '1';       -- 成功擊球 → 發短訊號
						end if;
					when RIGHT_SHIFT =>
						if (shift_reg="0000000001") then
							tx_sig1 <= '1';       -- 右端
						end if;
					when others => null;			
				end case;
			else 
				tx_sig1 <= '0';
			end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P2b] 只控制 tx_sig2（單拍）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst='0' then
            tx_sig2 <= '0';
        elsif rising_edge(i_clk) then
            tx_sig2 <= '0';
            case STATE is
                when LEFT_SHIFT =>
                    if ((shift_reg/="0100000000" and i_btn='1') or shift_reg="1000000000") then
                        tx_sig2 <= '1';       -- 失敗: 提早打擊 / 過頭
                    end if;
                when WAITING =>
                    if (i_btn='1' and server='0') then
                        tx_sig2 <= '1';       -- 失敗: 防守方早按
                    end if;
                when others => null;
            end case;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P3a] 只控制 drive_low（TX 脈衝）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst='0' then
            drive_low <= '0';
        elsif rising_edge(i_clk) then
            if drive_low='0' then
                if (tx_sig1='1' or tx_sig2='1') then
                    drive_low <= '1';         -- 開始拉低
                else
                    drive_low <= '0';
                end if;
            else
                -- 到達目標長度時放手
                if (tx_cnt >= (tx_target - C_ONE16)) then
                    drive_low <= '0';
                else
                    drive_low <= '1';
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P3b] 只控制 tx_cnt（向量計數）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst='0' then
            tx_cnt <= (others => '0');
        elsif rising_edge(i_clk) then
            if drive_low='0' then
                tx_cnt <= (others => '0');
            else
                if (tx_cnt >= (tx_target - C_ONE16)) then
                    tx_cnt <= (others => '0');
                else
                    tx_cnt <= tx_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P3c] 只控制 tx_target（以 1T / 2T 常數指定）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst='0' then
            tx_target <= (others => '0');
        elsif rising_edge(i_clk) then
            if drive_low='0' then
                if tx_sig1='1' then
                    tx_target <= C_1T;
                elsif tx_sig2='1' then
                    tx_target <= C_2T;
                else
                    tx_target <= tx_target; -- 保持
                end if;
            else
                if (tx_cnt >= (tx_target - C_ONE16)) then
                    tx_target <= (others => '0'); -- 結束清零
                else
                    tx_target <= tx_target;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P4] 只控制 shift_reg（慢時鐘推動）
    --------------------------------------------------------------------------
    process(slowClk, i_rst)
    begin
        if i_rst='0' then
            shift_reg <= "0100000000";         -- 左端預設
        elsif rising_edge(slowClk) then
            case STATE is
                when IDLE => 
                    if (server='1') then
                        shift_reg <= "0100000000";
                    else
                        shift_reg <= "0000000000";
                    end if;
                when RIGHT_SHIFT => shift_reg <= '0' & shift_reg(9 downto 1);
                when LEFT_SHIFT  => shift_reg <= shift_reg(8 downto 0) & '0';
                when WAITING     => shift_reg <= "0000000001";  -- 等待時右端待命
                when FAIL        => shift_reg <= '0' & point & '0'; -- 全向量指定，避免殘影
            end case;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P5] 只控制 server（發球權）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst='0' then
            server <= '1';
        elsif rising_edge(i_clk) then
            if (STATE=IDLE and rx_sig1='1') then
                server <= '0';
            elsif (STATE=RIGHT_SHIFT) then
                server <= '1';
            elsif (STATE=WAITING and server='1' and rx_sig1='1') then
                server <= '0';
            elsif (STATE=WAITING and rx_sig2='1') then
                server <= '1';
            elsif (STATE=LEFT_SHIFT and tx_sig2='1') then
                server <= '0';
            else
                server <= server;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P6] 只控制 o_led
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst='0' then
            o_led <= (others => '0');
        elsif rising_edge(i_clk) then
            o_led <= shift_reg(8 downto 1);
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P7] 計分（point：向量 +1）
    --------------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst='0' then
            point <= (others => '0');
        elsif rising_edge(i_clk) then
            if ( rx_sig2='1') then
                point <= point + 1;
            else
                point <= point;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- [P8] FAIL 計時
    --------------------------------------------------------------------------
    process(slowClk, i_rst)
    begin
        if i_rst='0' then
            cntTime <= (others => '0');
        elsif rising_edge(slowClk) then
            if STATE=FAIL then
                cntTime <= cntTime + 1;
            else
                cntTime <= (others => '0');
            end if;
        end if;
    end process;

end architecture;
