-- Atari Pong 實作 - VGA 640x480@60Hz，含球、板子與七段分數顯示邏輯
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

-- 頂層實體宣告，定義 I/O 介面
entity VGA_atariPong is
    port (
        i_clk   : in  std_logic;                   -- 25.175 MHz 時脈輸入
        i_rst   : in  std_logic;                   -- 低有效同步重設
        i_btnUp  : in  std_logic;                   -- 玩家板子上移按鈕
        i_btnDn  : in  std_logic;                   -- 玩家板子下移按鈕
        o_hsync : out std_logic;                   -- VGA 水平同步信號
        o_vsync : out std_logic;                   -- VGA 垂直同步信號
        o_red   : out std_logic_vector(2 downto 0);   -- 三位元紅色輸出
        o_green : out std_logic_vector(2 downto 0);   -- 三位元綠色輸出
        o_blue  : out std_logic_vector(2 downto 0)    -- 三位元藍色輸出
    );
end entity;

architecture Behavioral of VGA_atariPong is

    -- VGA timing 常數定義 (640×480@60Hz)
    constant H_DISPLAY : integer := 640;                 -- 水平可見畫面寬度 (visible area)
    constant H_FP      : integer := 16;                  -- 水平前肩 (front porch)
    constant H_SYNC    : integer := 96;                  -- 水平同步脈衝 (sync pulse)
    constant H_BP      : integer := 48;                  -- 水平後肩 (back porch)
    constant H_TOTAL   : integer := H_DISPLAY + H_FP + H_SYNC + H_BP;  -- 總水平週期

    constant V_DISPLAY : integer := 480;                 -- 垂直可見畫面高度
    constant V_FP      : integer := 10;                  -- 垂直前肩
    constant V_SYNC    : integer := 2;                   -- 垂直同步寬度
    constant V_BP      : integer := 33;                  -- 垂直後肩
    constant V_TOTAL   : integer := V_DISPLAY + V_FP + V_SYNC + V_BP;  -- 總垂直週期

    -- 遊戲用尺寸設定
    constant pad_hight : integer := 80;   -- 球拍高度
    constant pad_width : integer := 10;   -- 球拍寬度
    constant ball_size : integer := 10;   -- 球的邊長

    -- VGA 掃描計數器與畫面使能
    signal h_count : integer range 0 to H_TOTAL - 1 := 0;  -- 水平掃描計數
    signal v_count : integer range 0 to V_TOTAL - 1 := 0;  -- 垂直掃描計數
    signal video_on : std_logic;                            -- 畫面有效區標誌

    -- 遊戲狀態變數
    signal ball_x, ball_y : integer := 320;   -- 球的當前座標 (中心)
    signal ball_dx, ball_dy : integer := 2;   -- 球的水平與垂直速度
    signal pad1_y : integer := 210;           -- 左側玩家板子 Y 座標
    signal pad2_y : integer := 210;           -- 右側 AI 板子 Y 座標

    -- 時脈分頻與遊戲更新節奏
	signal cnt : std_logic_vector(25 downto 0);    -- 計數器
	signal slowClk : std_logic :='0';             

    -- 分數與遊戲結束旗標
    signal score1    : integer range 0 to 9 := 0;  -- 玩家1 分數 (0~9)
    signal score2    : integer range 0 to 9 := 0;  -- 玩家2 分數 (0~9)
    signal game_over : std_logic := '0';           -- 遊戲結束旗標

    -- 七段顯示器 LUT：index = 數字 0~9, bit6~bit0 = 段 A~G
    type seg7_array is array(0 to 9) of std_logic_vector(6 downto 0);
    constant seg7_lut : seg7_array := (
        "1111110", -- 0: A B C D E F
        "0110000", -- 1: B C
        "1101101", -- 2: A B D E G
        "1111001", -- 3: A B C D G
        "0110011", -- 4: B C F G
        "1011011", -- 5: A C D F G
        "1011111", -- 6: A C D E F G
        "1110000", -- 7: A B C
        "1111111", -- 8: A B C D E F G
        "1111011"  -- 9: A B C D F G
    );

begin
    ----------------------------------------------------------------
    -- 2次方除頻器
    ----------------------------------------------------------------
    
	-- 計數器 process
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            cnt <= (others => '0');
        elsif rising_edge(i_clk) then
            cnt <= cnt + 1;
        end if;
    end process;
    -- 取i_clk除以2^6為slowClk
    slowClk <= cnt(18);

    ----------------------------------------------------------------
    -- 水平掃描計數器 (h_count)、低有效重設
    ----------------------------------------------------------------
    --pocess: 
    process(i_clk, i_rst)
    begin
		if i_rst = '0' then                            -- 重設水平計數
            h_count <= 0;
        elsif rising_edge(i_clk) then                  
            if h_count = H_TOTAL - 1 then
                h_count <= 0;                          -- 本行結束，回 0
            else
                h_count <= h_count + 1;                -- 繼續掃描下一像素
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- 垂直掃描計數器 (v_count)、低有效重設
    ----------------------------------------------------------------
    process(i_clk, i_rst)
    begin
		if i_rst = '0' then                            -- 重設垂直計數
            v_count <= 0;
        elsif rising_edge(i_clk) then                          
            if h_count = H_TOTAL - 1 then              -- 每行結束時增加一列
                if v_count = V_TOTAL - 1 then
                    v_count <= 0;                      -- 全畫面結束，回 0
                else
                    v_count <= v_count + 1;
                end if;
            end if;
        end if;
    end process;

    -- 同步信號產生：H_SYNC、V_SYNC（低電位有效）
    o_hsync <= '0' when (h_count >= H_DISPLAY + H_FP and h_count < H_DISPLAY + H_FP + H_SYNC) else '1';
    o_vsync <= '0' when (v_count >= V_DISPLAY + V_FP and v_count < V_DISPLAY + V_FP + V_SYNC) else '1';

    -- 只有在可見區域內才顯示畫面
    video_on <= '1' when (h_count < H_DISPLAY and v_count < V_DISPLAY) else '0';

	------------------------------------------------------------------------
	-- ball_x 更新
	------------------------------------------------------------------------
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			ball_x <= H_DISPLAY/2;
		elsif rising_edge(slowClk) then
			if game_over = '0' then
				-- 垂直邊界反彈時不動
				if (ball_y <= 0) or (ball_y >= V_DISPLAY - ball_size) then
					ball_x <= ball_x;
				-- 左側板子碰撞
				elsif (ball_x <= pad_width) and
					  (ball_y >= pad1_y - ball_size) and (ball_y <= pad1_y + pad_hight) then
					ball_x <= ball_x - ball_dx;
				-- 右側板子碰撞
				elsif (ball_x >= H_DISPLAY - (pad_width + ball_size)) and
					  (ball_y >= pad2_y - ball_size) and (ball_y <= pad2_y + pad_hight) then
					ball_x <= ball_x - ball_dx;
				-- 左側出界 → 重置 X
				elsif (ball_x <= 0) then
					ball_x <= H_DISPLAY/2;
				-- 右側出界 → 重置 X
				elsif (ball_x >= H_DISPLAY - ball_size) then
					ball_x <= H_DISPLAY/2;
				-- 正常移動
				else
					ball_x <= ball_x + ball_dx;
				end if;
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- ball_y 更新
	------------------------------------------------------------------------
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			ball_y <= V_DISPLAY/2;
		elsif rising_edge(slowClk) then
			if game_over = '0' then
				-- 垂直邊界反彈
				if (ball_y <= 0) or (ball_y >= V_DISPLAY - ball_size) then
					ball_y <= ball_y - ball_dy;
				-- 左/右出界時重置 Y
				elsif (ball_x <= 0) or (ball_x >= H_DISPLAY - ball_size) then
					ball_y <= V_DISPLAY/2;
				-- 正常移動
				else
					ball_y <= ball_y + ball_dy;
				end if;
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- ball_dx 更新（水平方向速度）
	------------------------------------------------------------------------
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			ball_dx <= 3;
		elsif rising_edge(slowClk) then
			if game_over = '0' then
				-- 左側板子碰撞
				if (ball_x <= pad_width) and
				   (ball_y >= pad1_y - ball_size) and (ball_y <= pad1_y + pad_hight) then
					ball_dx <= -ball_dx;
				-- 右側板子碰撞
				elsif (ball_x >= H_DISPLAY - (pad_width + ball_size)) and
					  (ball_y >= pad2_y - ball_size) and (ball_y <= pad2_y + pad_hight) then
					ball_dx <= -ball_dx;
				-- 左/右出界也反向
				elsif (ball_x <= 0) or (ball_x >= H_DISPLAY - ball_size) then
					ball_dx <= -ball_dx;
				end if;
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- ball_dy 更新（垂直方向速度）
	------------------------------------------------------------------------
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			ball_dy <= 3;
		elsif rising_edge(slowClk) then
			if game_over = '0' then
				-- 垂直邊界反彈
				if (ball_y <= 0) or (ball_y >= V_DISPLAY - ball_size) then
					ball_dy <= -ball_dy;
				end if;
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- score1 更新（玩家1 得分）
	------------------------------------------------------------------------
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			score1 <= 0;
		elsif rising_edge(slowClk) then
			if game_over = '0' then
				if (ball_x >= H_DISPLAY - ball_size) then
					if score1 < 9 then
						score1 <= score1 + 1;
					end if;
				end if;
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- score2 更新（玩家2 得分）
	------------------------------------------------------------------------
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			score2 <= 0;
		elsif rising_edge(slowClk) then
			if game_over = '0' then
				if (ball_x <= 0) then
					if score2 < 9 then
						score2 <= score2 + 1;
					end if;
				end if;
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- game_over 更新（滿分結束判斷）
	------------------------------------------------------------------------
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			game_over <= '0';
		elsif rising_edge(slowClk) then
			if game_over = '0' then
				if (score1 = 9 and ball_x >= H_DISPLAY - ball_size) or
				   (score2 = 9 and ball_x <= 0) then
					game_over <= '1';
				end if;
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- pad1_y 更新（玩家1 板子移動）
	------------------------------------------------------------------------
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			pad1_y <= (V_DISPLAY/2) - (pad_hight/2);
		elsif rising_edge(slowClk) then
			if game_over = '0' then
				if (i_btnUp = '1') and (pad1_y > 0) then
					pad1_y <= pad1_y - 4;
				elsif (i_btnDn = '1') and (pad1_y < V_DISPLAY - pad_hight) then
					pad1_y <= pad1_y + 4;
				end if;
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- pad2_y 更新（AI 板子追球）
	------------------------------------------------------------------------
	process(slowClk, i_rst)
	begin
		if i_rst = '0' then
			pad2_y <= (V_DISPLAY/2) - (pad_hight/2);
		elsif rising_edge(slowClk) then
			if game_over = '0' then
				if (pad2_y + pad_hight/2 < ball_y) and (pad2_y + pad_hight < V_DISPLAY) then
					pad2_y <= pad2_y + 2;
				elsif (pad2_y + pad_hight/2 > ball_y) and (pad2_y > 0) then
					pad2_y <= pad2_y - 2;
				end if;
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- o_red 顏色輸出
	------------------------------------------------------------------------
	process(i_clk, i_rst)
	begin
		if i_rst = '0' then
			o_red <= "000";
		elsif rising_edge(i_clk) then
			if video_on = '1' then
				-- 球白色
				if (h_count >= ball_x and h_count < ball_x + ball_size) and
				   (v_count >= ball_y and v_count < ball_y + ball_size) then

					o_red <= "111";

				-- 左側板子紅色
				elsif (h_count < pad_width) and
					  (v_count >= pad1_y and v_count < pad1_y + pad_hight) then

					o_red <= "111";

				-- 右側板子藍色（red=0）
				elsif (h_count >= H_DISPLAY - pad_width) and
					  (v_count >= pad2_y and v_count < pad2_y + pad_hight) then

					o_red <= "000";

				-- 玩家1 分數段 A~G
				elsif seg7_lut(score1)(6) = '1' and h_count >= 200 and h_count < 240 and v_count >=  50 and v_count <  55 then
					o_red <= "111";  -- A
				elsif seg7_lut(score1)(5) = '1' and h_count >= 235 and h_count < 240 and v_count >=  55 and v_count <  85 then
					o_red <= "111";  -- B
				elsif seg7_lut(score1)(4) = '1' and h_count >= 235 and h_count < 240 and v_count >=  85 and v_count < 115 then
					o_red <= "111";  -- C
				elsif seg7_lut(score1)(3) = '1' and h_count >= 200 and h_count < 240 and v_count >= 110 and v_count < 115 then
					o_red <= "111";  -- D
				elsif seg7_lut(score1)(2) = '1' and h_count >= 200 and h_count < 205 and v_count >=  85 and v_count < 115 then
					o_red <= "111";  -- E
				elsif seg7_lut(score1)(1) = '1' and h_count >= 200 and h_count < 205 and v_count >=  55 and v_count <  85 then
					o_red <= "111";  -- F
				elsif seg7_lut(score1)(0) = '1' and h_count >= 200 and h_count < 240 and v_count >=  80 and v_count <  85 then
					o_red <= "111";  -- G

				-- 玩家2 分數段 A~G
				elsif seg7_lut(score2)(6) = '1' and h_count >= 390 and h_count < 430 and v_count >=  50 and v_count <  55 then
					o_red <= "111";
				elsif seg7_lut(score2)(5) = '1' and h_count >= 425 and h_count < 430 and v_count >=  55 and v_count <  85 then
					o_red <= "111";
				elsif seg7_lut(score2)(4) = '1' and h_count >= 425 and h_count < 430 and v_count >=  85 and v_count < 115 then
					o_red <= "111";
				elsif seg7_lut(score2)(3) = '1' and h_count >= 390 and h_count < 430 and v_count >= 110 and v_count < 115 then
					o_red <= "111";
				elsif seg7_lut(score2)(2) = '1' and h_count >= 390 and h_count < 395 and v_count >=  85 and v_count < 115 then
					o_red <= "111";
				elsif seg7_lut(score2)(1) = '1' and h_count >= 390 and h_count < 395 and v_count >=  55 and v_count <  85 then
					o_red <= "111";
				elsif seg7_lut(score2)(0) = '1' and h_count >= 390 and h_count < 430 and v_count >=  80 and v_count <  85 then
					o_red <= "111";

				-- 其他背景
				else
					o_red <= "000";
				end if;
			else
				o_red <= "000";
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- o_green 顏色輸出
	------------------------------------------------------------------------
	process(i_clk, i_rst)
	begin
		if i_rst = '0' then
			o_green <= "000";
		elsif rising_edge(i_clk) then
			if video_on = '1' then
				-- 球白色
				if (h_count >= ball_x and h_count < ball_x + ball_size) and
				   (v_count >= ball_y and v_count < ball_y + ball_size) then

					o_green <= "111";

				-- 左側板子紅色（green=0）
				elsif (h_count < pad_width) and
					  (v_count >= pad1_y and v_count < pad1_y + pad_hight) then

					o_green <= "000";

				-- 右側板子藍色（green=0）
				elsif (h_count >= H_DISPLAY - pad_width) and
					  (v_count >= pad2_y and v_count < pad2_y + pad_hight) then

					o_green <= "000";

				-- 玩家1 分數段 A~G
				elsif seg7_lut(score1)(6) = '1' and h_count >= 200 and h_count < 240 and v_count >=  50 and v_count <  55 then
					o_green <= "111";
				elsif seg7_lut(score1)(5) = '1' and h_count >= 235 and h_count < 240 and v_count >=  55 and v_count <  85 then
					o_green <= "111";
				elsif seg7_lut(score1)(4) = '1' and h_count >= 235 and h_count < 240 and v_count >=  85 and v_count < 115 then
					o_green <= "111";
				elsif seg7_lut(score1)(3) = '1' and h_count >= 200 and h_count < 240 and v_count >= 110 and v_count < 115 then
					o_green <= "111";
				elsif seg7_lut(score1)(2) = '1' and h_count >= 200 and h_count < 205 and v_count >=  85 and v_count < 115 then
					o_green <= "111";
				elsif seg7_lut(score1)(1) = '1' and h_count >= 200 and h_count < 205 and v_count >=  55 and v_count <  85 then
					o_green <= "111";
				elsif seg7_lut(score1)(0) = '1' and h_count >= 200 and h_count < 240 and v_count >=  80 and v_count <  85 then
					o_green <= "111";

				-- 玩家2 分數段 A~G
				elsif seg7_lut(score2)(6) = '1' and h_count >= 390 and h_count < 430 and v_count >=  50 and v_count <  55 then
					o_green <= "111";
				elsif seg7_lut(score2)(5) = '1' and h_count >= 425 and h_count < 430 and v_count >=  55 and v_count <  85 then
					o_green <= "111";
				elsif seg7_lut(score2)(4) = '1' and h_count >= 425 and h_count < 430 and v_count >=  85 and v_count < 115 then
					o_green <= "111";
				elsif seg7_lut(score2)(3) = '1' and h_count >= 390 and h_count < 430 and v_count >= 110 and v_count < 115 then
					o_green <= "111";
				elsif seg7_lut(score2)(2) = '1' and h_count >= 390 and h_count < 395 and v_count >=  85 and v_count < 115 then
					o_green <= "111";
				elsif seg7_lut(score2)(1) = '1' and h_count >= 390 and h_count < 395 and v_count >=  55 and v_count <  85 then
					o_green <= "111";
				elsif seg7_lut(score2)(0) = '1' and h_count >= 390 and h_count < 430 and v_count >=  80 and v_count <  85 then
					o_green <= "111";

				-- 其他背景
				else
					o_green <= "000";
				end if;
			else
				o_green <= "000";
			end if;
		end if;
	end process;

	------------------------------------------------------------------------
	-- o_blue 顏色輸出
	------------------------------------------------------------------------
	process(i_clk, i_rst)
	begin
		if i_rst = '0' then
			o_blue <= "000";
		elsif rising_edge(i_clk) then
			if video_on = '1' then
				-- 球白色
				if (h_count >= ball_x and h_count < ball_x + ball_size) and
				   (v_count >= ball_y and v_count < ball_y + ball_size) then

					o_blue <= "111";

				-- 左側板子紅色（blue=0）
				elsif (h_count < pad_width) and
					  (v_count >= pad1_y and v_count < pad1_y + pad_hight) then

					o_blue <= "000";

				-- 右側板子藍色
				elsif (h_count >= H_DISPLAY - pad_width) and
					  (v_count >= pad2_y and v_count < pad2_y + pad_hight) then

					o_blue <= "111";

				-- 玩家1 分數段 A~G（blue=0）
				elsif seg7_lut(score1)(6) = '1' and h_count >= 200 and h_count < 240 and v_count >=  50 and v_count <  55 then
					o_blue <= "000";
				elsif seg7_lut(score1)(5) = '1' and h_count >= 235 and h_count < 240 and v_count >=  55 and v_count <  85 then
					o_blue <= "000";
				elsif seg7_lut(score1)(4) = '1' and h_count >= 235 and h_count < 240 and v_count >=  85 and v_count < 115 then
					o_blue <= "000";
				elsif seg7_lut(score1)(3) = '1' and h_count >= 200 and h_count < 240 and v_count >= 110 and v_count < 115 then
					o_blue <= "000";
				elsif seg7_lut(score1)(2) = '1' and h_count >= 200 and h_count < 205 and v_count >=  85 and v_count < 115 then
					o_blue <= "000";
				elsif seg7_lut(score1)(1) = '1' and h_count >= 200 and h_count < 205 and v_count >=  55 and v_count <  85 then
					o_blue <= "000";
				elsif seg7_lut(score1)(0) = '1' and h_count >= 200 and h_count < 240 and v_count >=  80 and v_count <  85 then
					o_blue <= "000";

				-- 玩家2 分數段 A~G（blue=0）
				elsif seg7_lut(score2)(6) = '1' and h_count >= 390 and h_count < 430 and v_count >=  50 and v_count <  55 then
					o_blue <= "000";
				elsif seg7_lut(score2)(5) = '1' and h_count >= 425 and h_count < 430 and v_count >=  55 and v_count <  85 then
					o_blue <= "000";
				elsif seg7_lut(score2)(4) = '1' and h_count >= 425 and h_count < 430 and v_count >=  85 and v_count < 115 then
					o_blue <= "000";
				elsif seg7_lut(score2)(3) = '1' and h_count >= 390 and h_count < 430 and v_count >= 110 and v_count < 115 then
					o_blue <= "000";
				elsif seg7_lut(score2)(2) = '1' and h_count >= 390 and h_count < 395 and v_count >=  85 and v_count < 115 then
					o_blue <= "000";
				elsif seg7_lut(score2)(1) = '1' and h_count >= 390 and h_count < 395 and v_count >=  55 and v_count <  85 then
					o_blue <= "000";
				elsif seg7_lut(score2)(0) = '1' and h_count >= 390 and h_count < 430 and v_count >=  80 and v_count <  85 then
					o_blue <= "000";

				-- 其他背景
				else
					o_blue <= "000";
				end if;
			else
				o_blue <= "000";
			end if;
		end if;
	end process;



end architecture;
