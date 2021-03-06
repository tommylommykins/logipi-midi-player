library ieee;
use ieee.std_logic_1164.all;

library virtual_button_lib;
use virtual_button_lib.utils.all;
use virtual_button_lib.constants.all;

entity spi_tx is
  generic (
    cpol              : integer;
    cpha              : integer
    );
  port(
    ctrl : in ctrl_t;

    -- spi interface
    cs_n : in  std_logic;
    sclk : in  std_logic;
    miso : out std_logic;

    -- internal interface
    data                     : in  std_logic_vector(spi_word_length - 1 downto 0);
    latched_data             : out std_logic_vector(spi_word_length - 1 downto 0);
    data_fully_latched       : out std_logic
    );
end;

architecture rtl of spi_tx is

  ----------------------------------------------------------------------------------------------------
  -- Prevent metastability.
  ----------------------------------------------------------------------------------------------------
  signal sclk_d1, sclk_d2 : std_logic;
  signal cs_n_d1, cs_n_d2 : std_logic;
  signal mosi_d1, mosi_d2 : std_logic;

  signal ungated_miso : std_logic;

  signal bit_index : integer range 0 to spi_word_length;
  type state_t is (disabled, transmitting);

  -- Note the subtraction of 2 is correct. See the comment in process transmit.
  signal time_to_transmit : std_logic;

  constant bit_index_reset : integer := 0;

  signal latched_data_int    : std_logic_vector(spi_word_length - 1 downto 0);

  signal data_fully_latched_int : std_logic;
  signal data_tentatively_latched : std_logic;
  signal has_been_fully_latched : std_logic;
begin

  prevent_metastability : process (ctrl.clk) is
  begin
    if rising_edge(ctrl.clk) then
      sclk_d1 <= sclk;
      sclk_d2 <= sclk_d1;

      cs_n_d1 <= cs_n;
      cs_n_d2 <= cs_n_d1;

    end if;
  end process prevent_metastability;

  generate_time_to_transmit : process(sclk_d2, sclk_d1, cs_n_d2, cs_n_d1) is
    variable time_to_transmit_bool : boolean;
  begin
    if cpol = 0 and cpha = 0 then
      time_to_transmit_bool := (sclk_d2 = '1' and sclk_d1 = '0') or

                               --special case for transmitting first bit on
                               --fedge of chipselect
                               (cs_n_d2 = '1' and cs_n_d1 = '0');
      
    elsif cpol = 0 and cpha = 1 then
      time_to_transmit_bool := (sclk_d2 = '0' and sclk_d1 = '1') or
                               (cs_n_d2 = '1' and cs_n_d1 = '0');
      
    elsif cpol = 1 and cpha = 0 then
      time_to_transmit_bool := (sclk_d2 = '0' and sclk_d1 = '1');
      
    else
      time_to_transmit_bool := (sclk_d2 = '1' and sclk_d1 = '0');
      
    end if;

    if time_to_transmit_bool then
      time_to_transmit <= '1';
    else
      time_to_transmit <= '0';
    end if;
  end process;

  generate_latch : process(ctrl.clk) is
  begin
    if rising_edge(ctrl.clk) then
      if ctrl.reset_n = '0' then
        latched_data_int <= (others => '0');
      else
        if (cs_n_d2 = '1' and cs_n_d1 = '0' and has_been_fully_latched = '1') or
          (time_to_transmit = '1' and
           has_been_fully_latched = '1' and bit_index = 0)then
          latched_data_int         <= data;
          data_tentatively_latched <= '1';
        else
          data_tentatively_latched <= '0';
        end if;
      end if;
    end if;
  end process;

  select_next_bit : process(ctrl.clk)
  begin
    if rising_edge(ctrl.clk) then
      -- bit_index_reset is one greater than the number of bits in
      -- latched_data, and would thus fail to index. Do not read latched_data
      -- if this is the case.
      ungated_miso <= latched_data_int(bit_index);
    end if;
  end process;

  calc_bit_and_byte_index : process(ctrl.clk) is
    procedure reset_indices is
    begin
      bit_index           <= 0;
    end;

  begin
    if rising_edge(ctrl.clk) then
      if ctrl.reset_n = '0' then
        reset_indices;
      else
        if cs_n_d1 = '1' then
          reset_indices;

        -- This is the initial bit of a byte. Send the first bit of the data in
        -- the data port and latch the rest of it.
        elsif time_to_transmit = '1' then
          if bit_index = 0 then
            bit_index <= 7;
          else
            bit_index <= bit_index - 1;
          end if;
          
        end if;
      end if;
    end if;
  end process;

  gate_miso : process (cs_n, cs_n_d1, ungated_miso)
  begin
    if cs_n = '1' or cs_n_d1 = '1' then
      miso <= 'Z';
    else
      miso <= ungated_miso;
    end if;
  end process;

  --This process exists to get around problems where the fpga attempted to send
  --the next byte during the back porch. Since the back porch isn't actually
  --the start of a new byte, that byte never got sent.
  gen_second_bit_sent : process(ctrl.clk)
  begin
    if rising_edge(ctrl.clk) then
      if ctrl.reset_n = '0' then
        data_fully_latched_int <= '0';
      else
        if bit_index < 5 and bit_index /= 0 then
          data_fully_latched_int <= '1';
        else
          data_fully_latched_int <= '0';
        end if;

        if data_fully_latched_int = '1' then
          has_been_fully_latched <=  '1';
        elsif  data_tentatively_latched = '1' then
          has_been_fully_latched <= '0';
        end if;
      end if;
    end if;
  end process;


  data_fully_latched <= data_fully_latched_int;
  latched_data    <= latched_data_int;
end;
