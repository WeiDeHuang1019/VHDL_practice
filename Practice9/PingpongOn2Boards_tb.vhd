library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity PingpongOn2Boards_tb is
end;

architecture sim of PingpongOn2Boards_tb is
    ----------------------------------------------------------------------------
    -- TB 參數（與 DUT 一致；要加速可把 SLOW_DIV_POW2_TB 調小）
    ----------------------------------------------------------------------------
    constant CLK_HZ_TB        : integer := 10_000_000;  -- 10 MHz
    constant SLOW_DIV_POW2_TB : integer := 12;          -- tb 用 12（~0.8192 ms/步）
    constant PULSE_US_TB      : integer := 2;          -- 10 us 脈衝

    constant CLK_PERIOD : time := 100 ns;  -- 10 MHz
    -- slowClk 每步的週期：2^(SLOW_DIV_POW2+1) 個 clk 週期
    constant SLOW_DIV   : integer := 2**(SLOW_DIV_POW2_TB+1);
    constant SLOW_STEP  : time := CLK_PERIOD * SLOW_DIV;

    -- 幾何步數估算（從右端 bit1 到左端 bit8 約 7~8 步；抓 8 步較保守）
    constant STEPS_HALF : integer := 8;

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------
    signal clk   : std_logic := '0';
    signal rstn  : std_logic := '0';

    -- 單線匯流排（open-drain；TB 端持續提供弱上拉）
    signal link  : std_logic := 'H';

    -- A 節點
    signal A_btn : std_logic := '0';
    signal A_led : std_logic_vector(7 downto 0);

    -- B 節點
    signal B_btn : std_logic := '0';
    signal B_led : std_logic_vector(7 downto 0);

    ----------------------------------------------------------------------------
    -- 便捷的「按鍵按一下」程序（脈衝時間以 clk 週期為單位）
    ----------------------------------------------------------------------------
    procedure press(signal btn: out std_logic; for_time: time) is
    begin
        btn <= '1';
        wait for for_time;
        btn <= '0';
    end procedure;
begin
    ----------------------------------------------------------------------------
    -- Clock
    ----------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD/2;

    ----------------------------------------------------------------------------
    -- Weak pull-up：讓 link 永遠有個 'H' driver（遇到 '0' 會被拉成 '0'）
    ----------------------------------------------------------------------------
    link <= 'H';

    ----------------------------------------------------------------------------
    -- Reset
    ----------------------------------------------------------------------------
    process
    begin
        rstn <= '0';
        wait for 5 * CLK_PERIOD;
        rstn <= '1';
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- UUT A
    ----------------------------------------------------------------------------
    U_A: entity work.PingpongOn2Boards

        port map (
            i_clk  => clk,
            i_rst  => rstn,
            i_btn  => A_btn,
            io_bus => link,
            o_led  => A_led
        );

    ----------------------------------------------------------------------------
    -- UUT B
    ----------------------------------------------------------------------------
    U_B: entity work.PingpongOn2Boards

        port map (
            i_clk  => clk,
            i_rst  => rstn,
            i_btn  => B_btn,
            io_bus => link,
            o_led  => B_led
        );

    ----------------------------------------------------------------------------
    -- Stimulus：A 發球 → B 回擊 → A 失誤 → B 發球 → A 回擊 → B 失誤
    ----------------------------------------------------------------------------
    process
        -- 小工具：等 N 個 slow 步
        procedure wait_slow(n: integer) is
        begin
            wait for SLOW_STEP * n;
        end procedure;
    begin
        wait until rstn = '1';
        report "TB: reset deasserted" severity note;

        ------------------------------------------------------------------------
        -- 1) A 發球（A 在 IDLE 且有發球權時按一下）
        ------------------------------------------------------------------------
        report "A serve" severity note;
        press(A_btn, 3 * CLK_PERIOD);

        -- 從 A 發球到 A 打到右牆（→發短脈衝給 B）：約 8 步
        wait_slow(STEPS_HALF);

        -- B 收到短脈衝後進入 LEFT_SHIFT；再走到左端點大約再 8 步
        wait_slow(STEPS_HALF);

        ------------------------------------------------------------------------
        -- 2) B 回擊（在左端點按一下 → 成功擊球）
        ------------------------------------------------------------------------
        report "B return (hit at left endpoint)" severity note;
        press(B_btn, 3 * CLK_PERIOD);

        -- 從 B 擊球到 B 打到右牆（→發短脈衝給 A）：約 8 步
        wait_slow(STEPS_HALF);

        -- A 收到短脈衝後進入 LEFT_SHIFT；我們刻意「不是在左端點」太早按，造成失誤
        wait_slow(8);

        ------------------------------------------------------------------------
        -- 3) A 失誤（LEFT_SHIFT 非左端點時按 → 送長脈衝）
        ------------------------------------------------------------------------
        report "A fault (early press -> long pulse)" severity note;
        press(A_btn, 3 * CLK_PERIOD);

        -- FAIL 畫面維持幾個 slow 拍（你的 RTL 設計約 8 拍），等它回到 IDLE
        wait_slow(10);

        ------------------------------------------------------------------------
        -- 4) B 發球（因 A 失誤，發球權在 B）
        ------------------------------------------------------------------------
        report "B serve" severity note;
        press(B_btn, 3 * CLK_PERIOD);

        -- 從 B 發球到 B 打到右牆（→短脈衝給 A）：約 8 步
        wait_slow(STEPS_HALF);

        -- A 從右到左約 8 步：在左端點按一下 -> 回擊成功
        wait_slow(STEPS_HALF);

        ------------------------------------------------------------------------
        -- 5) A 回擊（在左端點按一下）
        ------------------------------------------------------------------------
        report "A return (hit at left endpoint)" severity note;
        press(A_btn, 3 * CLK_PERIOD);

        -- 從 A 擊球到 A 打到右牆（→短脈衝給 B）：約 8 步
        wait_slow(6);

        -- B 這次刻意在 WAITING 過早按，造成失誤
        
        ------------------------------------------------------------------------
        -- 6) B 失誤（早按 -> 長脈衝）
        ------------------------------------------------------------------------
        report "B fault (early press -> long pulse)" severity note;
        press(B_btn, 3 * CLK_PERIOD);

        wait_slow(12);

        report "TB finished scenario." severity note;
        wait;
    end process;
end architecture;
