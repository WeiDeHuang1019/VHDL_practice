library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity PingpongOn2Boards is
  generic (
    CLK_HZ        : integer := 10_000_000;  -- 模擬好看：10 MHz
    SLOW_DIV_POW2 : integer := 12;          -- 慢速位移用的除頻 bit（tb 用 12，真板可 23）
    PULSE_US      : integer := 10           -- 送交棒脈衝長度（固定寬度，us）
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
  -- 狀態
  --------------------------------------------------------------------------
  type STATE_T is (IDLE, RIGHT_SHIFT, LEFT_SHIFT, WAITING, FAIL);
  signal STATE : STATE_T := IDLE;

  --------------------------------------------------------------------------
  -- 慢時鐘 / 跑馬燈暫存
  --------------------------------------------------------------------------
  signal shift_reg : std_logic_vector(9 downto 0) := "0100000000"; -- 顯示取[8:1]
  signal counter   : unsigned(25 downto 0) := (others=>'0');
  signal slowClk   : std_logic;

  --------------------------------------------------------------------------
  -- 匯流排 I/O（open-drain）
  --------------------------------------------------------------------------
  signal drive_low : std_logic := '0';   -- '1'=拉低；否則三態
  signal bus_s0    : std_logic := '1';   -- 同步器 stage0
  signal bus_s1    : std_logic := '1';   -- 同步器 stage1
  signal bus_lvl   : std_logic := '1';   -- to_X01 後：'0'/'1'/'X'
  signal bus_prev  : std_logic := '1';   -- 前一拍

  -- RX 偵測（以匯流排邊緣 + 長度判斷）
  constant TICKS_PER_US     : integer := CLK_HZ/1_000_000;
  constant PULSE_TICKS      : integer := PULSE_US*TICKS_PER_US;
  constant RX_THRESH_TICKS  : integer := (3*PULSE_TICKS)/2; -- 1.5T 作為 1T/2T 分界
  signal rx_in_low          : std_logic := '0';             -- 對方拉低期間
  signal rx_cnt             : integer range 0 to 2*PULSE_TICKS := 0;
  signal rise_evt           : std_logic := '0';             -- 低→高之上升緣（對方放手）
  signal rx_sig1            : std_logic := '0';             -- 單拍：<=1.5T
  signal rx_sig2            : std_logic := '0';             -- 單拍：> 1.5T

  --------------------------------------------------------------------------
  -- TX 觸發 / 脈衝產生
  --------------------------------------------------------------------------
  signal tx_sig1      : std_logic := '0';                   -- 單拍觸發：1T
  signal tx_sig2      : std_logic := '0';                   -- 單拍觸發：2T
  signal tx_active    : std_logic := '0';                   -- 正在拉低
  signal tx_cnt       : integer range 0 to 2*PULSE_TICKS := 0;
  signal tx_T         : integer range 0 to 2 := 0;          -- 0:idle, 1:1T, 2:2T

  --------------------------------------------------------------------------
  -- 計分 / 計時
  --------------------------------------------------------------------------
  signal point        : integer range 0 to 127 := 0;
  signal cntTime      : unsigned(2 downto 0) := (others=>'0');

begin
  ----------------------------------------------------------------------------
  -- Open-drain：只拉低、不拉高；其餘時間交給上拉
  ----------------------------------------------------------------------------
  io_bus <= '0' when drive_low='1' else 'Z';

  ----------------------------------------------------------------------------
  -- [PS0] 只控 bus_s0：第一級同步
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      bus_s0 <= '1';
    elsif rising_edge(i_clk) then
      bus_s0 <= io_bus;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [PS1] 只控 bus_s1：第二級同步
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      bus_s1 <= '1';
    elsif rising_edge(i_clk) then
      bus_s1 <= bus_s0;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [PS2] 只控 bus_lvl：正規化（把 'H' 視為 '1'）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      bus_lvl <= '1';
    elsif rising_edge(i_clk) then
      bus_lvl <= to_X01(bus_s1); -- 'H'→'1'，'Z'/'U'→'X'
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [PS3] 只控 bus_prev：保留上一拍
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      bus_prev <= '1';
    elsif rising_edge(i_clk) then
      bus_prev <= bus_lvl;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [PR0] 只控 rx_in_low：在我沒拉低時，偵測 bus 高→低/低→高
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      rx_in_low <= '0';
    elsif rising_edge(i_clk) then
      if drive_low='0' then
        if (bus_prev='1' and bus_lvl='0') then       -- 下降緣：開始拉低
          rx_in_low <= '1';
        elsif (bus_prev='0' and bus_lvl='1') then     -- 上升緣：放手
          rx_in_low <= '0';
        end if;
      else
        rx_in_low <= '0';                              -- 我在拉低→不接收
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [PR1] 只控 rx_cnt：low 期間計數
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      rx_cnt <= 0;
    elsif rising_edge(i_clk) then
      if rx_in_low='1' then
        if rx_cnt < 2*PULSE_TICKS then
          rx_cnt <= rx_cnt + 1;
        end if;
      else
        rx_cnt <= 0;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [PR2] 只控 rise_evt：在我沒拉低時偵測 bus 低→高 上升緣（對方放手）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      rise_evt <= '0';
    elsif rising_edge(i_clk) then
      if (drive_low='0' and bus_prev='0' and bus_lvl='1') then
        rise_evt <= '1';
      else
        rise_evt <= '0';
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [PR3] 只控 rx_sig1：單拍（<=1.5T 視為 1T）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      rx_sig1 <= '0';
    elsif rising_edge(i_clk) then
      if (rise_evt='1' and rx_cnt <= RX_THRESH_TICKS) then
        rx_sig1 <= '1';
      else
        rx_sig1 <= '0';
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [PR4] 只控 rx_sig2：單拍（>1.5T 視為 2T）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      rx_sig2 <= '0';
    elsif rising_edge(i_clk) then
      if (rise_evt='1' and rx_cnt > RX_THRESH_TICKS) then
        rx_sig2 <= '1';
      else
        rx_sig2 <= '0';
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- 慢時鐘
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      counter <= (others=>'0');
    elsif rising_edge(i_clk) then
      counter <= counter + 1;
    end if;
  end process;
  slowClk <= std_logic(counter(SLOW_DIV_POW2));  -- 取某 bit 當慢節拍

  ----------------------------------------------------------------------------
  -- [P1] 只控 STATE（狀態轉移）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      STATE <= IDLE;
    elsif rising_edge(i_clk) then
      case STATE is
        when IDLE =>
          if i_btn='1' then
            STATE <= RIGHT_SHIFT;
          elsif rx_sig1='1' then
            STATE <= WAITING;             -- 對面宣告佔用 → 我等待
          else
            STATE <= IDLE;
          end if;

        when RIGHT_SHIFT =>
          if (shift_reg = "0000000010") then
            STATE <= WAITING;             -- 到右端：發 1T（由 tx_sig1 產生）後等
          else
            STATE <= RIGHT_SHIFT;
          end if;

        when LEFT_SHIFT =>
          if (shift_reg = "0100000000" and i_btn='1') then
            STATE <= RIGHT_SHIFT;         -- 成功擊球
          elsif (tx_sig2='1') then        -- 你定義的失敗事件會觸發 2T
            STATE <= FAIL;
          else
            STATE <= LEFT_SHIFT;
          end if;

        when WAITING =>
          if (rx_sig1='1') then
            STATE <= LEFT_SHIFT;          -- 收到交棒 → 我開始跑
          elsif (rx_sig2='1') then
            STATE <= FAIL;                -- 收到 2T → Fail
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

  ----------------------------------------------------------------------------
  -- [PT1] 只控 tx_sig1（單拍觸發）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      tx_sig1 <= '0';
    elsif rising_edge(i_clk) then
      tx_sig1 <= '0';  -- 單拍
      case STATE is
        when IDLE =>
          if i_btn='1' then
            tx_sig1 <= '1';               -- 起跑：1T
          end if;
        when RIGHT_SHIFT =>
          if shift_reg="0000000010" then
            tx_sig1 <= '1';               -- 抵達右端：1T
          end if;
        when others =>
          null;
      end case;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [PT2] 只控 tx_sig2（單拍觸發）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      tx_sig2 <= '0';
    elsif rising_edge(i_clk) then
      tx_sig2 <= '0';  -- 單拍
      case STATE is
        when LEFT_SHIFT =>
          if ((shift_reg="0100000000" and i_btn/='1') or shift_reg="1000000000") then
            tx_sig2 <= '1';               -- 擊球失敗：2T
          end if;
        when others =>
          null;
      end case;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [TXA] 只控 tx_active（是否正在拉低）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      tx_active <= '0';
    elsif rising_edge(i_clk) then
      if tx_active='0' then
        if (tx_sig1='1' or tx_sig2='1') then
          tx_active <= '1';
        end if;
      else
        -- 到點由 tx_cnt/tx_T 判斷，這裡只在完成時清零
        if tx_cnt >= (tx_T*PULSE_TICKS)-1 then
          tx_active <= '0';
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [TXB] 只控 tx_cnt（拉低期間計數）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      tx_cnt <= 0;
    elsif rising_edge(i_clk) then
      if tx_active='1' then
        tx_cnt <= tx_cnt + 1;
      else
        tx_cnt <= 0;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [TXC] 只控 tx_T（1T 或 2T）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      tx_T <= 0;
    elsif rising_edge(i_clk) then
      if tx_active='0' then
        if tx_sig1='1' then
          tx_T <= 1;
        elsif tx_sig2='1' then
          tx_T <= 2;
        end if;
      else
        if tx_cnt >= (tx_T*PULSE_TICKS)-1 then
          tx_T <= 0;                      -- 完成後回 0
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [TXD] 只控 drive_low（真正的 open-drain 拉低控制）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      drive_low <= '0';
    elsif rising_edge(i_clk) then
      drive_low <= '1' when tx_active='1' else '0';
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [P4] 只控 shift_reg（慢時鐘推動）
  ----------------------------------------------------------------------------
  process(slowClk, i_rst)
  begin
    if i_rst='0' then
      shift_reg <= "0100000000";
    elsif rising_edge(slowClk) then
      case STATE is
        when IDLE        => shift_reg <= "0100000000";
        when RIGHT_SHIFT => shift_reg <= '0' & shift_reg(9 downto 1);
        when LEFT_SHIFT  => shift_reg <= shift_reg(8 downto 0) & '0';
        when WAITING     => shift_reg <= "0000000001";      -- 等待時在右端待命
        when FAIL        => shift_reg(8 downto 1) <= std_logic_vector(to_unsigned(point,8)); -- 顯示分數
      end case;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [P5] 只控 o_led（顯示）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      o_led <= (others=>'0');
    elsif rising_edge(i_clk) then
      o_led <= shift_reg(8 downto 1);
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [P6] 只控 point（計分）
  ----------------------------------------------------------------------------
  process(i_clk, i_rst)
  begin
    if i_rst='0' then
      point <= 0;
    elsif rising_edge(i_clk) then
      if (STATE = WAITING and rx_sig2='1') then
        if point < 127 then
          point <= point + 1;
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- [P7] 只控 cntTime（FAIL 計時）
  ----------------------------------------------------------------------------
  process(slowClk, i_rst)
  begin
    if i_rst='0' then
      cntTime <= (others=>'0');
    elsif rising_edge(slowClk) then
      if STATE = FAIL then
        cntTime <= cntTime + 1;
      else
        cntTime <= (others=>'0');
      end if;
    end if;
  end process;

end architecture;
