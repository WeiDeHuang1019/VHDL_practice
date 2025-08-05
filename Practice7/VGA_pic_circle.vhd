library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity VGA_pic is
    port (
        i_clk  : in  std_logic;  -- 25.175 MHz clock
        i_rst  : in  std_logic;
        o_hsync  : out std_logic;
        o_vsync  : out std_logic;
        o_red    : out std_logic_vector(2 downto 0);
        o_green  : out std_logic_vector(2 downto 0);
        o_blue   : out std_logic_vector(2 downto 0)
    );
end entity;

architecture Behavioral of VGA_pic is

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
    signal in_circle : STD_LOGIC := '0';

begin

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

    -- o_hsync control (active low)
    process(h_count)
    begin
        if h_count >= H_DISPLAY + H_FP and h_count < H_DISPLAY + H_FP + H_SYNC then
            o_hsync <= '0';
        else
            o_hsync <= '1';
        end if;
    end process;

    -- o_vsync control (active low)
    process(v_count)
    begin
        if v_count >= V_DISPLAY + V_FP and v_count < V_DISPLAY + V_FP + V_SYNC then
            o_vsync <= '0';
        else
            o_vsync <= '1';
        end if;
    end process;
	
	-- in_circle detect
	process(h_count, v_count)
		variable dx, dy  : integer;
		constant RADIUS : integer := 10;
		constant R2     : integer := RADIUS * RADIUS;
	begin
	    
		in_circle <= '0';

		dx := h_count - 40;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle <= '1';
		end if;

		dx := h_count - 120;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle <= '1';
		end if;

		dx := h_count - 200;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle <= '1';
		end if;

		dx := h_count - 280;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle <= '1';
		end if;

		dx := h_count - 360;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle <= '1';
		end if;

		dx := h_count - 440;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle <= '1';
		end if;

		dx := h_count - 520;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle <= '1';
		end if;

		dx := h_count - 600;
		dy := v_count - 240;
		if (dx * dx + dy * dy <= R2) then
			in_circle <= '1';
		end if;
	end process;

	--RGB output
	process(i_clk)
	begin
		if rising_edge(i_clk) then
			if h_count < H_DISPLAY and v_count < V_DISPLAY then
				if in_circle = '1' then
					o_red   <= "111";
					o_green <= "111";
					o_blue  <= "111";
				else
					o_red   <= "111";
					o_green <= "000";
					o_blue  <= "000";
				end if;
			else
				o_red   <= "000";
				o_green <= "000";
				o_blue  <= "000";
			end if;
		end if;
	end process;


end architecture;
