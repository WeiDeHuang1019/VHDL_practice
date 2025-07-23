library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity VGA_pingpong is
    port (
        i_clk  : in  std_logic;  -- 25.175 MHz clock
        i_rst  : in  std_logic;
        i_btn1  : in  STD_LOGIC;
        i_btn2  : in  STD_LOGIC;
        o_led   : out STD_LOGIC_VECTOR(7 downto 0);
        hsync  : out std_logic;
        vsync  : out std_logic;
        red    : out std_logic_vector(2 downto 0);
        green  : out std_logic_vector(2 downto 0);
        blue   : out std_logic_vector(2 downto 0)
    );
end entity;

architecture Behavioral of VGA_pingpong is

    -- pingpong game
    type STATE_TYPE is (IDLE, RIGHT_SHIFT, LEFT_SHIFT, FAIL);

    signal STATE         : STATE_TYPE ;
    signal PRE_STATE     : STATE_TYPE ;

    signal led         : STD_LOGIC_VECTOR(7 downto 0);
    signal shift_reg     : STD_LOGIC_VECTOR(9 downto 0);  
    signal counter       : STD_LOGIC_VECTOR(25 downto 0);
    signal cntTime       : STD_LOGIC_VECTOR(3 downto 0);
    signal cntPoint1     : STD_LOGIC_VECTOR(3 downto 0);
    signal cntPoint2     : STD_LOGIC_VECTOR(3 downto 0);

    signal slowClk       : STD_LOGIC ;  

    -- VGA 640x480 @60Hz timing
    constant H_DISPLAY : integer := 640;
    constant H_FP      : integer := 16;
    constant H_SYNC    : integer := 96;
    constant H_BP      : integer := 48;
    constant H_TOTAL   : integer := H_DISPLAY + H_FP + H_SYNC + H_BP;

    constant V_DISPLAY : integer := 480;
    constant V_FP      : integer := 10;
    constant V_SYNC    : integer := 2;
    constant V_BP      : integer := 33;
    constant V_TOTAL   : integer := V_DISPLAY + V_FP + V_SYNC + V_BP;

    signal h_count : integer range 0 to H_TOTAL - 1 := 0;
    signal v_count : integer range 0 to V_TOTAL - 1 := 0;
    signal in_circle : STD_LOGIC_vector(1 downto 0) := "00";
    
    constant C_X : integer := 320;
    constant C_Y : integer := 240;

begin

    --process clockDivider
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            counter <= (others => '0');
        elsif rising_edge(i_clk) then
            counter <= counter + 1;
        else
            counter <= counter;     
        end if;
    end process;
    slowClk <= counter(23);

    --process FSM
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            STATE <= IDLE;
        elsif rising_edge(i_clk) then
            PRE_STATE <= STATE;
            case STATE is
                when IDLE =>
                    if (i_btn1 = '1' and shift_reg = "0100000000") then
                        STATE <= RIGHT_SHIFT;
                    else
                        STATE <= IDLE;
                    end if;
                when RIGHT_SHIFT =>
                    if shift_reg = "0000000001" then
                        STATE <= FAIL;
                    elsif (shift_reg = "0000000010" and i_btn2 = '1') then
                        STATE <= LEFT_SHIFT;
                    elsif (i_btn2 = '1' and shift_reg /= "0000000010") then
                        STATE <= FAIL;
                    else
                        STATE <= RIGHT_SHIFT;
                    end if;
                when LEFT_SHIFT =>
                    if shift_reg = "1000000000" then
                        STATE <= FAIL;
                    elsif (shift_reg = "0100000000" and i_btn1 = '1') then
                        STATE <= RIGHT_SHIFT;
                    elsif (i_btn1 = '1' and shift_reg /= "0100000000") then
                        STATE <= FAIL;
                    else
                        STATE <= LEFT_SHIFT;
                    end if;
                when FAIL =>
                    if cntTime = "0111" then
                        STATE <= IDLE;
                    else
                        STATE <= FAIL;
                    end if;
            end case;
        end if;
    end process;

    --process LED_SHIFT
    process(slowClk, i_rst)
    begin
        if i_rst = '0' then
            shift_reg <= "0100000000";
        elsif rising_edge(slowClk) then
            case STATE is
                when IDLE =>
                    shift_reg <= "0100000000";
                when RIGHT_SHIFT =>
                    shift_reg <= '0' & shift_reg(9 downto 1);
                when LEFT_SHIFT =>
                    shift_reg <= shift_reg(8 downto 0) & '0';
                when FAIL =>
                    shift_reg <= shift_reg; 
            end case;
        end if;
    end process;

    --process LED_output
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            led <= "10000000";
        elsif rising_edge(i_clk) then
            case STATE is
                when IDLE =>
                    led <= "10000000";
                when RIGHT_SHIFT =>
                    led <= shift_reg(8 downto 1);
                when LEFT_SHIFT =>
                    led <= shift_reg(8 downto 1);
                when FAIL =>
                    led(7 downto 4) <= cntPoint1;
                    led(3 downto 0) <= cntPoint2;
            end case;
        end if;
    end process;
    o_led <= led;

    --process timer
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

    --process pointCountLeft
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            cntPoint1 <= (others => '0');
        elsif rising_edge(i_clk) then
            case STATE is
                when FAIL =>
                    if (PRE_STATE = RIGHT_SHIFT or PRE_STATE = IDLE) then
                        cntPoint1 <= cntPoint1 + 1;
                    else
                        cntPoint1 <= cntPoint1;
                    end if;
                when others =>
                    cntPoint1 <= cntPoint1;   
            end case;
        end if;
    end process;

    --process pointCountRight
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            cntPoint2 <= (others => '0');
        elsif rising_edge(i_clk) then
            case STATE is
                when FAIL =>
                    if PRE_STATE = LEFT_SHIFT then
                        cntPoint2 <= cntPoint2 + 1;
                    else
                        cntPoint2 <= cntPoint2;
                    end if;
                when others =>
                    cntPoint2 <= cntPoint2;   
            end case;
        end if;
    end process;

    -- Horizontal counter
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            h_count <= 0;
        elsif rising_edge(i_clk) then
            if h_count = H_TOTAL - 1 then
                h_count <= 0;
            else
                h_count <= h_count + 1;
            end if;
        end if;
    end process;

    -- Vertical counter
    process(i_clk, i_rst)
    begin
        if i_rst = '0' then
            v_count <= 0;
        elsif rising_edge(i_clk) then
            if h_count = H_TOTAL - 1 then
                if v_count = V_TOTAL - 1 then
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
                end if;
            end if;
        end if;
    end process;

    -- HSync control (active low)
    process(h_count)
    begin
        if h_count >= H_DISPLAY + H_FP and h_count < H_DISPLAY + H_FP + H_SYNC then
            hsync <= '0';
        else
            hsync <= '1';
        end if;
    end process;

    -- VSync control (active low)
    process(v_count)
    begin
        if v_count >= V_DISPLAY + V_FP and v_count < V_DISPLAY + V_FP + V_SYNC then
            vsync <= '0';
        else
            vsync <= '1';
        end if;
    end process;
	
	-- in_circle detect
	process(h_count, v_count)
		variable dx, dy  : integer;
		constant RADIUS : integer := 10;
		constant R2     : integer := RADIUS * RADIUS;
	begin
	    
		in_circle <= "00";

		dx := h_count - 40;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle(0) <= led(7);
			in_circle(1) <= '1';
		end if;

		dx := h_count - 120;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle(0) <= led(6);
			in_circle(1) <= '1';
		end if;

		dx := h_count - 200;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle(0) <= led(5);
			in_circle(1) <= '1';
		end if;

		dx := h_count - 280;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle(0) <= led(4);
			in_circle(1) <= '1';
		end if;

		dx := h_count - 360;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle(0) <= led(3);
			in_circle(1) <= '1';
		end if;

		dx := h_count - 440;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle(0) <= led(2);
			in_circle(1) <= '1';
		end if;

		dx := h_count - 520;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle(0) <= led(1);
			in_circle(1) <= '1';
		end if;

		dx := h_count - 600;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle(0) <= led(0);
			in_circle(1) <= '1';
		end if;
	end process;

	--RGB output
	process(i_clk)
	begin
		if rising_edge(i_clk) then
			if h_count < H_DISPLAY and v_count < V_DISPLAY then
				if in_circle = "11" then
					red   <= "111";
					green <= "000";
					blue  <= "000";
				elsif in_circle = "10" then
					red   <= "111";
					green <= "111";
					blue  <= "111";
				else
					red   <= "000";
					green <= "000";
					blue  <= "000";
				end if;
			else
				red   <= "000";
				green <= "000";
				blue  <= "000";
			end if;
		end if;
	end process;


end architecture;
