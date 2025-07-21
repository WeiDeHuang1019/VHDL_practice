library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity VGA_pic_tb is
-- Testbench 不需要 Port
end VGA_pic_tb;

architecture Behavioral of VGA_pic_tb is

    -- Component 宣告
    component VGA_pic
        Port (
            i_clk     : in  STD_LOGIC;
            i_rst       : in  STD_LOGIC;      
            hsync     : out STD_LOGIC;
            vsync     : out STD_LOGIC;
            red       : out STD_LOGIC_VECTOR (2 downto 0);
            green     : out STD_LOGIC_VECTOR (2 downto 0);
            blue      : out STD_LOGIC_VECTOR (2 downto 0)
        );
    end component;

    -- Signals for connection
    signal i_clk     : STD_LOGIC := '0';
    signal i_rst       :STD_LOGIC;
    signal hsync     : STD_LOGIC;
    signal vsync     : STD_LOGIC;
    signal red       : STD_LOGIC_VECTOR (2 downto 0);
    signal green     : STD_LOGIC_VECTOR (2 downto 0);
    signal blue      : STD_LOGIC_VECTOR (2 downto 0);

begin

    -- DUT (Device Under Test) instantiation
    uut: VGA_pic
        Port map (
            i_clk => i_clk,
            i_rst => i_rst,
            hsync => hsync,
            vsync => vsync,
            red   => red,
            green => green,
            blue  => blue
        );

    -- Generate 25 MHz clock: 40ns period
    rst_process : process
    begin
        i_rst <= '0';            -- active low
        wait for 100 ns;         -- hold reset 100ns
        i_rst <= '1';
        wait;
    end process;    
    
    clk_process :process
    begin
        while True loop
            i_clk <= '0';
            wait for 5 ns;
            i_clk <= '1';
            wait for 5 ns;
        end loop;
    end process;

end Behavioral;
