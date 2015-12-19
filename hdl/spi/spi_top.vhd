library IEEE;
use IEEE.STD_LOGIC_1164.all;

library virtual_button_lib;
use virtual_button_lib.utils.all;
use virtual_button_lib.constants.all;

entity spi_top is
  generic(
    tx_ram_depth : integer;
    block_size   : integer;
    cpol         : integer;
    cpha         : integer
    );
  port(
    ctrl : in ctrl_t;

    --hardware interface
    cs_n                  : in  std_logic;
    sclk                  : in  std_logic;
    mosi                  : in  std_logic;
    miso                  : out std_logic;
    request_more_from_mcu : out std_logic;

    -- internal receive interface
    new_mcu_to_fpga_data : out std_logic;
    mcu_to_fpga_data     : out std_logic_vector(spi_word_length - 1 downto 0);

    -- internal tx interface
    enqueue_fpga_to_mcu_data : in std_logic;
    fpga_to_mcu_data         : in std_logic_vector(spi_word_length - 1 downto 0);


    -- debug from transmitter
    next_byte_index : out integer range 0 to block_size - 1;
    full            : out std_logic;
    contents_count  : out integer range 0 to tx_ram_depth
    );
end spi_top;

architecture rtl of spi_top is
  signal fpga_to_mcu_data_latched : std_logic;
  signal header_byte              : std_logic_vector(7 downto 0);
  signal read_out_data            : std_logic_vector(7 downto 0);
  signal tx_header_byte           : std_logic;
  signal next_tx_byte             : std_logic_vector(7 downto 0);
  signal dequeue                  : std_logic;
  signal empty                    : std_logic;

  signal contents_count_int : integer range 0 to tx_ram_depth;
begin

  spi_tx_1 : entity virtual_button_lib.spi_tx
    generic map (
      cpol       => cpol,
      cpha       => cpha,
      block_size => block_size)
    port map (
      ctrl            => ctrl,
      cs_n            => cs_n,
      sclk            => sclk,
      miso            => miso,
      data            => next_tx_byte,
      data_latched    => fpga_to_mcu_data_latched,
      next_byte_index => next_byte_index);

  spi_rx_1 : entity virtual_button_lib.spi_rx
    generic map (
      cpol => cpol,
      cpha => cpha)
    port map (
      ctrl     => ctrl,
      sclk     => sclk,
      cs_n     => cs_n,
      mosi     => mosi,
      data     => mcu_to_fpga_data,
      new_data => new_mcu_to_fpga_data);

  tx_fifo : entity work.circular_queue
    generic map(
      queue_depth => tx_ram_depth
      )
    port map (
      ctrl           => ctrl,
      enqueue        => enqueue_fpga_to_mcu_data,
      dequeue        => dequeue,
      write_in_data  => fpga_to_mcu_data,
      read_out_data  => read_out_data,
      empty          => empty,
      full           => full,
      contents_count => contents_count_int);

  tx_controller : entity virtual_button_lib.spi_tx_ram_controller
    generic map(
      block_size => block_size)
    port map(
      ctrl => ctrl,

      fpga_to_mcu_data_latched => fpga_to_mcu_data_latched,
      contents_count           => contents_count_int,

      tx_header_byte => tx_header_byte,
      header_byte    => header_byte,
      dequeue        => dequeue,

      --hardware interface
      request_more_data => request_more_from_mcu
      );

  select_tx_data : process(read_out_data, tx_header_byte, header_byte) is
  begin
    if tx_header_byte = '1' then
      next_tx_byte <= header_byte;
    else
      next_tx_byte <= read_out_data;
    end if;
  end process;

  contents_count <= contents_count_int;

end rtl;
