input_offset = 0
base = 0
rng = 0xFFFFFFFF

MASK32 = 0xFFFFFFFF

class packer_model:
	def __init__(self, threshold, num_symbols):
		self.threshold = threshold
		self.current_num_symbols = num_symbols
		self.num_symbols = []
		for i in range(self.current_num_symbols):
			self.num_symbols.append(1)

	def get_dword_input_stream(self):
		global input_offset, byte_data

		b1 = byte_data[input_offset + 0]
		b2 = byte_data[input_offset + 1]
		b3 = byte_data[input_offset + 2]
		b4 = byte_data[input_offset + 3]
		return 256 * 256 * 256 * b1 + 256 * 256 * b2 + 256 * b3 + b4

	def enlarge_range(self, new_base, new_range):
		global input_offset

		input_offset += 1
		return new_base * 256, new_range * 256

	def normalize(self, new_base, new_range):
		global input_offset

		while True:
			new_base &= MASK32
			new_range &= MASK32

			if (((new_base + new_range) & MASK32) ^ new_base) < 0x01000000:
				pass
			elif new_range >= 0x00010000:
				break
			else:
				new_range = (-new_base) & 0xFFFF

			input_offset += 1
			new_base = (new_base << 8) & MASK32
			new_range = (new_range << 8) & MASK32

		return new_base, new_range

	def get_next_byte(self):
		global base, rng

		range_per_one_frequency = rng // self.current_num_symbols

		current_data = (self.get_dword_input_stream() - base) & MASK32
		ranges_input_stream = current_data // range_per_one_frequency
		ranges_count = ranges_input_stream

		current_symbol = 0
		while True:
			ranges_input_stream -= self.num_symbols[current_symbol]
			if ranges_input_stream < 0:
				break
			current_symbol += 1

		old_frequency = self.num_symbols[current_symbol]
		self.num_symbols[current_symbol] += 2

		mee = - (ranges_input_stream + old_frequency)
		mee += ranges_count
		mee *= range_per_one_frequency
		mee = (mee + base) & MASK32

		old_frequency *= range_per_one_frequency

		new_base, new_range = mee, old_frequency
		base, rng = self.normalize(new_base, new_range)
		self.current_num_symbols += 2

		if self.current_num_symbols >= self.threshold:
			for i in range(len(self.num_symbols)):
				half_frequency = self.num_symbols[i] // 2
				self.num_symbols[i] -= half_frequency
				self.current_num_symbols -= half_frequency

		return current_symbol

	def read_bits_in_cycle(self):
		current_result = 1

		while True:
			two_bits = self.get_next_byte()
			current_result = current_result * 2 + (two_bits % 2)
			if two_bits // 2 == 0:
				break

		return current_result

def copy_previous_displacement():
	size = model_2.read_bits_in_cycle()
	copy_from_previous_data(old_displacement, size)

def copy_previous_displacement_and_size():
	high_nibble = (model_1.read_bits_in_cycle() & MASK32) - 2

	if high_nibble < 0:
		return -1
	if high_nibble == 0:
		low_nibble = model_5.get_next_byte()
	else:
		low_nibble = model_6.get_next_byte()
	displacement = 16 * high_nibble + low_nibble + 1
	size = model_2.read_bits_in_cycle()

	if displacement >= 0x800:
		size += 1
	if displacement >= 0x60:
		size += 1

	copy_from_previous_data(displacement, size)
	return 0

def copy_from_previous_data(displacement, size):
	global old_displacement

	old_displacement = displacement

	current_size = len(result)
	for i in range(size):
		result.append(result[-displacement])


with open('pno0001.exe', 'rb') as packed:
	packed.seek(0xD4)
	byte_data = packed.read(1000000)		# MORE THAN NEEDED

model_7 = packer_model(128, 2)
model_6 = packer_model(384, 16)
model_5 = packer_model(128, 16)
model_4 = packer_model(64, 2)
model_3 = packer_model(64, 2)
model_2 = packer_model(192, 4)
model_1 = packer_model(384, 4)
model_0 = packer_model(1024, 256)

result = []
special_flow = -1
check_special = 0
old_displacement = 0

while True:
	if check_special == 0:
		value = model_0.get_next_byte()
		result.append(value)
		special_flow = 3

	if special_flow == 3:
		check_special = model_3.get_next_byte()
	else:
		check_special = model_4.get_next_byte()

	if check_special == 0:
		continue

	if special_flow == 4:
		res = copy_previous_displacement_and_size()
		if res == -1:
			break
	else:
		check_old_displacement = model_7.get_next_byte()
		if check_old_displacement == 0:
			res = copy_previous_displacement_and_size()
			if res == -1:
				break
		else:
			copy_previous_displacement()
	special_flow = 4

with open('kkrunchy_unpack_part1.out', 'wb') as f:
        f.write(bytes(result))
