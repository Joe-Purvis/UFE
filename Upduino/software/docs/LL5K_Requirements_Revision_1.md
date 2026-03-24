LL5K Requirements to support the UPduino iCE40UP5K board.

1. Purpose (one paragraph)
	Define what the LL5K must do, what it must not do, and what interfaces it exposes.
	The UPduino is the heart of the control system and is a deterministic method to control a signal generator, data transmission and reception.
	What UPduino does not do:
		- It does not generate any waveforms.
		- It does not perform any DSP operations.
	What UPduino does do:	
		- Controls when the signal generator is active and monitors when the signal generator becomes inactive.
		- Controls the Transmit, Receive and Clear (PZT) switches.
		- Accumulates receive data bit-by-bit (1 bit per burst) and stores the resultant 0 or 1 that the analog output determines.

	OFF = LOGIC 0
	ON = LOGIC 1

2. Subsystem Overview (what exists in fabric)

	Subsystem - PC-UART
		The PC-UART is the serial interface between the PC and the UPduino, communication is via the PC's COM port / FTDI TTL232-RG cable. 
	
	Subsystem - US-UART
		The US-UART is the serial interface between the piezoelectric transducer and the embedded slave module.
		This interface is a hybrid system of Amplitude Modulated (AM) ultrasound for data transmission (lowest power required for the decoding the incident signal) and ultrasound echo / reflection (lowest power required for the slave module).
	
	PZT-FSM
		The PZT-FSM comprises, a Moore architecture.
		This is preferred since it is synchronised with a clock, which is often safer in complex hardware systems avoiding potential timing errors.
		
		The PZT-FSM sets switch timing and receive bit validity.
	
	To be considered:-
	- PC-UART front-end + register access layer
	- Register file / memory map decode
	- TX/RX control FSM interface (if applicable)
	- Trigger/burst timing interface
	- GPIO + button conditioning
	- Diagnostics (LEDs, counters, error flags)
	- Data capture / FIFO (only if required)

2.1 PC PC-UART (control/telemetry)
	Physical: 
		DATA-IN (L) = pin 24
		DATA-OUT = pin 25
		Clock: 12 MHz on-board device (SJ16 on the board should be jumpered).
		Direction:
			RX (PC->LL5K): configuration writes, commands
			TX (LL5K->PC): readback, status, streaming telemetry (if any)
		
		Every externally-sourced signal is buffered via a 74LVC17 for physical protection and polarity preservation.
		Every externally-sinked signal is buffered via a 74LVC17 for physical protection and polarity preservation.
  
	2.1.1 PC-UART Protocol and Framing (Authoritative)
			This section defines the complete and frozen PC-UART framing used by the LL5K register interface. 
			Once validated, this framing is considered stable; any incompatible change shall require a VERSION register increment and be treated as a breaking change.

	2.1.2 PC-UART Physical Layer
			Big endian system.
			Asynchronous PC-UART
			8 data bits, no parity, 1 stop bit (8N1)
			LSB transmitted first.
			No flow control
			Baud rate defined by system configuration (default 9600 baud)

	2.1.3 Transaction Model (Host-Initiated, Request/Response)
			All PC-UART exchanges are host-initiated. 
			The LL5K device never transmits spontaneously; it transmits exactly one response frame per validly received request frame initiated by the host (PC / MATLAB).
			All PC-UART transactions are byte-oriented request/response exchanges 
				One Request Frame from host to LL5K
				One Response Frame from LL5K to host

	2.1.4 Request Frame Format
			All requests use the following fixed 5-byte format:

			ByteIndex	Field	Description
				0		SYNC	Request sync byte = 0x55
				1		OP		Operation code
				2		ADDR	8-bit register address
				3		DATA	Data byte (used for WRITE, ignored for READ)
				4		CHK		Check byte
			
			SYNC (Request): Fixed value: 0x55
				Used for byte alignment and frame resynchronisation.

			OP (Operation Code):fixed mapping
				The OP field is frozen as follows:

				OP Value	Meaning
				0x01		READ8 request
				0x02		WRITE8 request

				No other OP values are currently defined. Unsupported OP codes shall generate an error response.

			ADDR: 8-bit register address.
				The address space rabge is a possible 256 locations: 0x00–0xFF.

			DATA
				For WRITE8: byte written to the addressed register.
				For READ8: ignored by LL5K (host may set to 0x00).
			
			CHK (Requext Check Byte)
				Check byte provides lightweight integrity checking.
				Defined as XOR of the first 4 bytes:
					CHK = SYNC ⊕ OP ⊕ ADDR ⊕ DATA
				Requests with incorrect CHK are rejected and generate an error response.
				

	2.1.5 Response Frame Format
			All responses use the following fixed 5-byte format:
			
			Byte Index	Field	Description
				0		SYNC	Response sync byte = 0x56
				1		STATUS	Status / result code
				2		ADDR	Echoed register address
				3		DATA	Read data or echoed write data
				4		CHK		Check byte
		
			SYNC (Response): Fixed value of 0x56
				Intentionally different from request SYNC (0x55) to	simplify debugging and resynchronisation.

			STATUS
				The STATUS byte encodes the outcome of the request:

				STATUS	Meaning
				0x00	OK – operation successful
				0x01	Invalid OP code
				0x02	Invalid address
				0x03	Check byte (CHK) error
				0x04	Write to read-only register
				0x05	Internal error

				Additional status codes may be added in future revisions but existing codes shall not change meaning.

			ADDR
				Echo of the ADDR field from the request.
				Allows host to correlate responses even if frames are delayed or retried.

			DATA
				For READ8: data read from the addressed register.
				For WRITE8: echoed write data (for verification).
				
			CHK (Response Check Byte)
				Defined as XOR of the first 4 response bytes:
				CHK = SYNC ⊕ STATUS ⊕ ADDR ⊕ DATA
				Host shall verify CHK before accepting response data.

	2.1.6 Error Handling and Response Policy
			Requests with invalid CHK:-
				Are rejected.
				A response shall still be transmitted, with STATUS = CHK error.
			
			Requests with unsupported OP or invalid ADDR:
				Generate a response with the corresponding STATUS code.

			LL5K shall never silently drop a correctly framed request.

	2.1.7 Determinism and Timing Guarantees
			Response is generated only after full request reception and validation.
			PC-UART transmit and receive operations are decoupled internally; RX may still be active while TX begins.
			No timing assumptions shall be made by the host other than eventual response or timeout.

	2.2 US-UART
		The US-UART uses two mechanisms for data transfer through a medium depending upon whether the phase is data transmission or data reception.
		The protocol and framing for US-UART follows the same protocol as the PC-UART model.
		Transmission
			Transmission of data to the slave device is acheived by amplitude modulation (AM) of a transmitted ultrasound wave.
			The data for transmission is written into a dedicated US-TXD register.
			There are two ways to initiate a transmission frame.
				- Press external pushbutton switch USER1.
				- Write a '1' into Control Register bit ?.
				
		Reception
			Data reception relies on modulation of the slave device's piezoelectric reflection coefficient.
			There are two distinct phases to receive data from the slave.
				- Transmission of a short burst of ultrasound targeted to the slave's piezoelectric receiver.
				- Monitoring and detection of any received echo from the transmission burst. 
				
		PZT-FSM timing
			The PZT-FSM is derived from the 12MHz on-board clock, offering a clock period of 83.3333ns.
			There are two ways to initiate the PZT-FSM, these are:-
				- Upon the rising edge of USER1 pushbutton being activated.
				- By writing a '1' into Control register bit 
			PZT-FSM timing is initiated by the falling edge of FPGA-Burst-Sync. 
			This indicates that the signal generator has completed a sine-wave burst transmission and that the system should prepare for echo detection.
			There are ? phases involved in the PZT-FSM cycle, these are introduced below:-
			
				
				- TXD Switch OFF
				- PZT Switch ON
				- PZT Switch OFF
				- RXD Switch ON
				- RXD Switch OFF
				- RX-Bit read		
				
## 3. External Interfaces
### 3.1 Control / IO (board-level)

- External Inputs
	MODE pushbutton switch
		Protection provided.
		Debounce required.
		Syncronisation required.
		This signal is buffered.
		
	PB_USER1 pushbutton switch
		Protection provided.
		Debounce required.
		Syncronisation required.
		This signal is buffered.
		
	PB_USER2 pushbutton switch
		Protection provided.
		Debounce required.
		Syncronisation required.
		This signal is buffered.		
		
	EXT-BURST-SYNC
		This signal originates at the signal generator and is TTL/CMOS.
		Physical protection provided on the board.
		The rising edge of this signal indicates a burst has begun from the TG5011A. 
		The falling edge of this signal indicates that the signal burst has completed.
		The purpose of this signal is to determine when the TXD switch / RXD switch and PZT switch should be activated.
		This signal is buffered.
	
	EXT-DATA-IN
		This is the serial data input from the PC via the FTDI PC-UART / COM port.
		This signal is buffered.
		
- External Outputs
	EXT-TXD
		This signal is a serial data output to the TG5011A's MOD-IN BNC. 
		This digital signal modulates the TG5011A's sine wave amplitude.
		The amplitude modulation is decoded by the remote backscatter board.
		This signal is buffered. 
		The TG5011A will accept a signal from +5v to -5v.
		
	EXT-TRIG-OUT
		This signal is the control signal that is applied to the TRIG-IN BNC of the TG5011A and indicates that the instrument should begin it's output sine wave burst.
		The TG5011A will accept a signal from +10v to -10v.
		This signal is buffered.
		
	EXT-DATA-OUT
		This is the serial data output from the FTDI PC-UART / COM port TO the PC.
		This signal is buffered.

- Internal-only signals (no protection needed)
	TX_WINDOW_ACTIVE
		This signal indicates that the TXD switch must be active.
		
	RX_WINDOW_ACTIVE
		This signal indicates that the RXD switch must be active.
		
	PZT_DAMP_EN
		This signal indicates that the PZT switch must be active
	
	RST_INT	
		RST_INT is used to reset the integrator following an integration period, ensuring the charge on the integration capacitor always begins at 0v.

	RX_BIT
		RX-BIT is the result of the decision regarding whether an echo has been received => logic '1' or no echo has been received '0' in the limited 'receive window'.
		This decision is an analog threshold given by the PZT receive circuit and an external comparator.

## 4. Non-Functional Requirements
- Reset behavior (power-up defaults)
	Following power-up reset the TX_WINDOW_ACTIVE, RX_WINDOW_ACTIVE and PZT_DAMP_EN signals must all be OFF.
	EXT-TRIG-OUT is selectable as high/rising edge or low/falling edge ON THE TG5011A instrument. In this application make the reset state = 0.
	EXT-TXD is connected to the MOD-IN connector and will be ignored unless modulation is selected. In this application make the reset state = 0.
	RST_INT = 1
	Soft-Reset and POR do exactly the same thing.
	Reset all control outputs and registers.
- Clock domains (assume single 12 MHz unless explicitly needed)
- CDC policy (2FF sync for async inputs; FIFOs for data if needed)
- Determinism / latency targets
- Test strategy: module TBs + top-level integration TB

## 5. Memory Map (proposed)
Define a simple address map. Example structure:
	Control Register
	Status Register
	PC to SmartSwitch Input Data Register
	SmartSwitch to PC Output Data Register
	RX Register
	

### 5.1 Register access model
- Address width: 8-bit
- Data width: 8-bit
- Endianness: Little Endian
- Atomicity: (define multi-byte write/read behavior)

### 5.2 Register table

	0x00: ID (RO)  : device ID / build tag
		Default Layout & Value:-
		D7 D6 D5 D4 D3 D2 D1 D0
		 0  0  0  0  0  0  0  1

	0x01: VERSION (RO)
		Default Layout & Value:-
		D7 D6 D5 D4 D3 D2 D1 D0
		 0  0  0  0  0  0  0  1

	0x02: CONTROL REGISTER (RW)
		Data is stored as shown below.
		D7 D6 D5 D4 D3 D2 D1 D0
		
		Default Bit Layout:-
		TXD	RXD PZT 0 0 0 PZT_GO POR
	
		Default value:-
		0 0 0 0 0 0 0 0
	
		TXD = 0 indicates that the TX_WINDOW is inactive.
		TXD = 1 initiates the TX_WINDOW to be active.
		During normal operation TXD is set and cleared by the FSM.
		For diagnostic purposes TXD can be set to 1 if and only if the RXD bit and PZT bit are already OFF.
	
		RXD = 0 indicates that the RX_WINDOW is inactive.
		RXD = 1 initiates the RX_WINDOW to be active.
		During normal operation RXD is set and cleared by the FSM.
		For diagnostic purposes RXD can be set to 1 if and only if the TXD bit and PZT bit are already OFF.
	
		PZT = 0 indicates that the PZT_DRAIN_WINDOW is inactive.
		PZT = 1 initiates the PZT_DRAIN_WINDOW to be active.
		During normal operation PZT is set and cleared by the FSM.
		For diagnostic purposes PZT can be set to 1 if and only if the TXD bit and RXD bit are already OFF.
		
		PZT_GO = 0 indicates that the PZT-FSM is inactive.
		PZT_GO = 1 initiates the PZT-FSM to be active.
		During normal operation PZT is set and cleared by the FSM.
		For diagnostic purposes PZT can be set to 1 if and only if the TXD bit and RXD bit are already OFF.

		POR is a self-clearing bit. 
		Writing a '1' to the POR bit resets all the internal registers including RX accumulator pointer, RXD-RDY, ERR flag and PC-UART parser state and the signals TX_WINDOW_ACTIVE, RX_WINDOW_ACTIVE, PZT_DAMP_EN.
		
	0x03: STATUS REGISTER (RO)
		Data is stored as shown below.
		D7 D6 D5 D4 D3 D2 D1 D0
		
		Default Bit Layout:-
		RST_INT ERR RDY 0 0 0 PZT_GO 0
	
		Default value:-
		0 0 0 0 0 0 0 0		
	
		RST_INT = 0 indicates that the integrator is RESET.
		RST_INT = 1 indicates that the integrator is NOT RESET.
		
		ERR = 1 indicates that an illegal operation was attempted.
		Safe Policy - Ignore illegal requests, set the ERR bit.
		This bit will be cleared automatically upon reading the status register.
		
		RDY = 0 indicates the RXD register is not ready to be read.
		RDY = 1 indicates the RXD register is ready to be read.
		This bit is polled to determine if the RXD Register is full.
		
		PZT_GO = 0 indicates that the PZT_FSM is idle.
		PZT_GO = 1 indicates the the PZT_FSM is active.
	
	0x04: IRQ_EN (RW) / IRQ_STAT (W1C) (optional)
		TBD TBD TBD TBD TBD TBD TBD TBD 

	0x10: RXD_Accumulator (WO)
		Default Layout & Value:-
		D7 D6 D5 D4 D3 D2 D1 D0
		 0  0  0  0  0  0  0  0
		
		Operation:-
		Following the end of every RX_WINDOW_ACTIVE period the value of the RX_BIT is sampled on the first falling edge of RX_WINDOW_ACTIVE being de-asserted, the value of the RX_BIT is stored in this register.
		RX_BIT samples are accumulated internally in this register (from bit 0 first through to bit 7 last).
		When the register is full:-
			The byte is copied into the RXD register.
			The RXD accumulator is cleared back to 0x00.
			RDY flag is set.
	
	0x11: RXD_Data_Register (R/W)
		Default Layout & Value:-
		D7 D6 D5 D4 D3 D2 D1 D0
		 0  0  0  0  0  0  0  0
	
		The transmission of further frames is prevented until the RXD register is read.
		Any attempt to initiate another transmission will cause the ERR flag to be set.
		After the RXD register has been read the register is reset and the ERR flag is cleared.
		
	0x20: Divisor_Register (R/W)
		Default Layout & Value:-
		D7 D6 D5 D4 D3 D2 D1 D0
		 0  0  0  0  1  1  0  0
		
		The value of this register is the required division for the PZT-FSM.
		The default value is 0x0C.
		The lowest value possible is 0x01.
			
	0x21: PZT_CLAMP_START_TIME	
		D7 D6 D5 D4 D3 D2 D1 D0
		 0  0  0  0  0  0  0  1
		 
	0x22: PZT_CLAMP_STOP_TIME	
		D7 D6 D5 D4 D3 D2 D1 D0
		 0  0  0  0  0  0  1  0	

	0x23: RECEIVE_WINDOW_START_TIME	
		D7 D6 D5 D4 D3 D2 D1 D0
		 0  0  0  0  0  0  1  1		
		 
	0x24: RECEIVE_WINDOW_STOP_TIME	
		D7 D6 D5 D4 D3 D2 D1 D0
		 0  0  0  0  0  0  1  1			 
	
	0x30: US-UART Data Register
		Data is stored as shown below.
		D7 D6 D5 D4 D3 D2 D1 D0
		

### 5.3 Error handling
- Framing/parity/overrun flags
- Unknown address access behavior
- Timeouts (if any)

## 6. PC-UART Protocol (initial)
	Frame definitions (v0)
		Common
		SYNC = 0x55 (single-byte start marker)
		ADDR = 8-bit (0x00–0xFF)
		CRC8 = 8-bit CRC-8 using polynomial 0x07, initial value 0x00, no input reflection, no output reflection, and no final XOR. 
		The CRC is computed over all bytes from OP through the final payload byte (SYNC excluded).
		
	WRITE8 request (PC → LL5K)
		[0] SYNC   = 0x55
		[1] OP     = 0x01
		[2] ADDR
		[3] DATA
		[4] CRC8
	
	READ8 request (PC → LL5K)
		[0] SYNC   = 0x55
		[1] OP     = 0x02
		[2] ADDR
		[3] CRC8
	
	READ8 response (LL5K → PC)
		[0] SYNC   = 0x55
		[1] OP     = 0x82
		[2] ADDR
		[3] DATA
		[4] CRC8
		
	WRITE8 response
		[0] SYNC   = 0x55
		[1] OP     = 0x81
		[2] ADDR
		[3] STATUS  (0x00=OK, nonzero=error)
		[4] CRC8

	Error/status codes (STATUS byte)
		0x00 OK
		0x01 CRC error
		0x02 Unknown OP
		0x03 Invalid address (unimplemented register)
		0x04 Write to RO register

## 7. Open Decisions
SPI Display Port