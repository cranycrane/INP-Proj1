-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <login AT stud.fit.vutbr.cz>
--
  library ieee;
  use ieee.std_logic_1164.all;
  use ieee.std_logic_arith.all;
  use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (

   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 

   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );



end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
-- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
--   - nelze z vice procesu ovladat stejny signal,
--   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
--      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
--      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 

architecture behavioral of cpu is
 -- PTR - Ukazatel do paměti dat
 signal PTR : std_logic_vector(12 downto 0); --  čítač
 signal ptr_inc : std_logic; -- signál pro inkrementaci
 signal ptr_dec : std_logic; -- signál pro dekrementaci
 
-- PC - Programový čítač  
signal PC : std_logic_vector(12 downto 0); -- programový čítač
signal pc_inc : std_logic; -- signál pro inkrementaci
signal pc_dec : std_logic; -- signál pro dekrementaci

-- CNT - Pocitac cyklu
signal CNT : std_logic_vector(12 downto 0); -- programový čítač
signal cnt_inc : std_logic; -- signál pro inkrementaci
signal cnt_dec : std_logic; -- signál pro dekrementaci


-- incMem(>), decMem(<), incValue(+), decValue(-), openWhile([), closeWhile(])
-- break(~), putChar(~), getChar(,), endProgram(@)
 
type inst_type is (incMem, decMem, incValue, decValue, openWhile, closeWhile, 
break, putChar, getChar, endProgram, skip);
signal ireg_dec : inst_type;

-- Not sure jestli potrebuju fetch0 a fetch1
-- ve fetch0 povolit cteni z pameti, ve fetch1 nacitat a prejit do decode stavu???

type fsm_state is (sidle, sinit, sfindSign, sfetch, sfetch1, sdecode, sincMem, sdecMem, sincValue, sincValue1,
                  sdecValue, sdecValue1, sopenWhile, sopenWhile1, sgoOnEnd, sgoOnStart, sskip,
                   scloseWhile, scloseWhile1, sbreak, sputChar, sputChar1, sputCharWait, sgetChar, sgetCharWait, sendProgram);
signal pstate : fsm_state;
signal nstate : fsm_state;

-- MX1 - Multiplexor 
signal sel_mx1 : std_logic;

-- MX2 - Multiplexor
signal sel_mx2 : std_logic_vector(1 downto 0);



begin

  




 -- PTR ukazatel do pameti dat
PTR_reg: process (CLK, RESET)
 begin
   if (RESET = '1') then
     PTR <= (others => '0');
   elsif (CLK'event) and (CLK='1') then
     if ptr_inc = '1' then
       PTR <= PTR + 1;
     elsif ptr_dec = '1' then
       PTR <= PTR - 1;
     end if;
   end if;
 end process;


 -- PC programový čítač
PC_reg: process (CLK, RESET)
begin
  if (RESET = '1') then
    PC <= (others => '0');
  elsif (CLK'event) and (CLK='1') then
    if pc_inc = '1' then
      PC <= PC + 1;
    elsif pc_dec = '1' then
      PC <= PC - 1;
    end if;
  end if;
end process;

 -- PC programový čítač
CNT_reg: process (CLK, RESET)
 begin
   if (RESET = '1') then
     CNT <= (others => '0');
   elsif (CLK'event) and (CLK='1') then
     if cnt_inc = '1' then
       CNT <= CNT + 1;
     elsif cnt_dec = '1' then
       CNT <= CNT - 1;
     end if;
   end if;
 end process;

-- MX1 pro prepinani CNT a PTR do pameti
MX1: process (sel_mx1, PC, PTR)
begin
    if sel_mx1 = '0' then
      DATA_ADDR <= PC;
    elsif sel_mx1 = '1' then
      DATA_ADDR <= PTR;
    end if;
end process;

-- MX pro pro prepinani +1, -1, IN_DATA
MX2: process (sel_mx2, DATA_RDATA)
begin
    case sel_mx2 is
        when "01" =>  -- Předpokládáme 2-bitový výběrový signál
            DATA_WDATA <= DATA_RDATA - 1;  -- snížení o 1
        when "10" =>
            DATA_WDATA <= DATA_RDATA + 1;  -- zvýšení o 1
        when "11" =>
            DATA_WDATA <= IN_DATA;  -- propojení s IN_DATA
        when others =>

    end case;
end process;

 


 -- Instruction decoder
 process (DATA_RDATA)
 begin
  case DATA_RDATA is
    when X"3E" => ireg_dec <= incMem;
    when X"3C" => ireg_dec <= decMem;
    when X"2B" => ireg_dec <= incValue;
    when X"2D" => ireg_dec <= decValue;
    when X"5B" => ireg_dec <= openWhile;
    when X"5D" => ireg_dec <= closeWhile;
    when X"7E" => ireg_dec <= break;
    when X"2E" => ireg_dec <= putChar;
    when X"2C" => ireg_dec <= getChar;
    when X"40" => ireg_dec <= endProgram;
    when others =>
      ireg_dec <= skip;
    end case;
 end process;




-- FSM Present state
fsm_pstate: process (RESET, CLK)
begin
  if (RESET='1') then
    pstate <= sinit;

  elsif (CLK'event) and (CLK='1') then
    if (EN='1') then
      pstate <= nstate;

    end if;
  end if;
end process;

-- FSM next state logic, output logic
nsl: process (ireg_dec, pstate, DATA_RDATA)
begin
-- INIT


case pstate is
  when sinit =>
    READY <= '0';
    DONE <= '0';
    --DATA_ADDR <= (others => '0');
    --DATA_WDATA <= (others => '0');
    DATA_RDWR <= '0';
    DATA_EN <= '0'; ---- 1
    IN_REQ <= '0';
    OUT_WE <= '0';
    OUT_DATA <= (others => '0');

    pc_inc <= '0';
    pc_dec <= '0';
    ptr_inc <= '0';
    ptr_dec <= '0';

    cnt_inc <= '0';
    cnt_dec <= '0';

    sel_mx1 <= '0';
    sel_mx2 <= "00";
    nstate <= sfindSign;

  when sidle =>
    nstate <= sfindSign;

  when sskip =>
    pc_inc <= '1';
    nstate <= sfetch;

  when sfetch =>
    sel_mx1 <= '0';
    sel_mx2 <= "00";
    ptr_inc <= '0'; -- Nastavit ZA '@'
    ptr_dec <= '0';
    pc_inc <= '0';
    DATA_RDWR <= '0';
    DATA_EN <= '1';
    OUT_WE <= '0';
    OUT_DATA <= (others => '0');
    nstate <= sfetch1;

  when sfetch1 =>
    nstate <= sdecode;

  when sfindSign =>
    sel_mx1 <= '1';
    ptr_inc <= '1';
    DATA_EN <= '1';

    if DATA_RDATA = X"40" then  -- Nasel si @?
      READY <= '1';
      ptr_inc <= '0';
      nstate <= sfetch;
    end if;



  when sdecode =>
    case ireg_dec is
      when endProgram =>
        nstate <= sendProgram;
      when incMem =>
        nstate <= sincMem;
      when decMem =>
        nstate <= sdecmem;
      when incValue =>
        nstate <= sincValue;
      when decValue =>
        nstate <= sdecValue;
      when putChar =>
        nstate <= sputChar;
      when getChar =>
        nstate <= sgetChar;
      when openWhile =>
        nstate <= sopenWhile;
      when closeWhile =>
        nstate <= scloseWhile;
      when break =>
        nstate <= sbreak;
      when skip =>
        nstate <= sskip;
      
      when others => 
    end case;
    
-- ENDPROGRAM
    when sendProgram =>
      DONE <= '1';
      nstate <= sendProgram;

-- INCMEM
    when sincMem =>
      pc_inc <= '1';
      ptr_inc <= '1';
      nstate <= sfetch;

-- DECMEM
    when sdecmem =>
      pc_inc <= '1';
      ptr_dec <= '1';
      nstate <= sfetch;

-- INCVALUE
    when sincValue =>
    DATA_EN <= '1';
    DATA_RDWR <= '0';
    sel_mx2 <= "10";
    sel_mx1 <= '1';
    nstate <= sincValue1;
    when sincValue1 =>
      DATA_RDWR <= '1';
      pc_inc <= '1';
      DATA_EN <= '1';
      nstate <= sfetch;

-- DECVALUE
    when sdecValue =>
    DATA_EN <= '1';
    DATA_RDWR <= '0';
    sel_mx2 <= "01";
    sel_mx1 <= '1';
    nstate <= sdecValue1;
    when sdecValue1 =>
      DATA_RDWR <= '1';
      pc_inc <= '1';
      DATA_EN <= '1';
      nstate <= sfetch;
-- PUTCHAR
    when sputChar =>
      if OUT_BUSY = '0' then
        
        sel_mx1 <= '1';
        
        pc_inc <= '1';
        nstate <= sputChar1;
      elsif OUT_BUSY = '1' then
        nstate <= sputCharWait;
      end if;
    when sputChar1 =>
      OUT_WE <= '1';
      OUT_DATA <= DATA_RDATA;
      pc_inc <= '0';
      nstate <= sfetch;
    when sputCharWait =>
        nstate <= sputChar;
-- GETCHAR
    when sgetChar =>
        IN_REQ <= '1';
        sel_mx1 <= '1';
        if IN_VLD = '0' then -- cekam
          nstate <= sgetCharWait;
        elsif IN_VLD = '1' then
          DATA_RDWR <= '1';
          IN_REQ <= '0';
          sel_mx2 <= "11";
          pc_inc <= '1';   
          nstate <= sfetch;       
        end if;
    when sgetCharWait =>
        nstate <= sgetChar;
-- OPEN WHILE
    when sopenWhile =>
      pc_inc <= '1';
      sel_mx1 <= '1';
      nstate <= sopenWhile1;
    when sopenWhile1 =>
      pc_inc <= '0';
      -- mem[ptr] == 0
      if DATA_RDATA = "00000000" then
        sel_mx1 <= '0';
        nstate <= sgoOnEnd;
      -- mem[ptr] != 0 - pokracuju dal
      else 
        sel_mx1 <= '0';
        nstate <= sfetch;
      end if;
-- *PTR = 0 -> JDEME ZA ']'
    when sgoOnEnd =>
        pc_inc <= '1';
        if ireg_dec = closeWhile then
          pc_inc <= '0';
          nstate <= sfetch;
        else 
          nstate <= sgoOnEnd;
        end if;

-- CLOSE WHILE

    when scloseWhile =>
      sel_mx1 <= '1';
      nstate <= scloseWhile1;
    when scloseWhile1 =>
      sel_mx1 <= '0';
      -- mem[ptr] == 0
      if DATA_RDATA = "00000000" then
        pc_inc <= '1';
        nstate <= sfetch;
      else
        nstate <= sgoOnStart;
      end if;
-- ZPATKY NA ZACATEK CYKLU, PRED '['
    when sgoOnStart =>
      pc_dec <= '1';
      if ireg_dec = openWhile then
        pc_dec <= '0';
        pc_inc <= '1';
        nstate <= sfetch;
      else
        nstate <= sgoOnStart;
      end if;  
-- BREAK the LOOP
    when sbreak =>
        nstate <= sgoOnEnd;


    when others => 
end case;
end process;

end behavioral;