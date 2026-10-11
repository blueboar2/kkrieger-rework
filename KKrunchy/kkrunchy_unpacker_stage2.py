offsets = [0x605]
table_normal = []
table_0f = []
last_jmp = 0

data_offset = 0x3B257

result = []

def read_from(stream_num, packed):
	offset = offsets[stream_num]
	packed.seek(offset)
	offsets[stream_num] += 1
	next_byte = packed.read(1)
	next_int = int.from_bytes(next_byte)
	return next_int

def store_dword(dword):
	global result

	for i in range(4):
		result.append(dword % 256)
		dword //= 256

with open('kkrunchy_unpacker_stage1.out', 'rb') as packed:
	packed.seek(0x5B1)
	for i in range(20):
		four_bytes = packed.read(4)
		segment_len = int.from_bytes(four_bytes, 'little')
		offsets.append(offsets[-1] + segment_len)

	packed.seek(0x1FC)
	for i in range(128):
		read_byte = packed.read(1)
		read_int = int.from_bytes(read_byte)
		table_normal.append(read_int % 16)
		table_normal.append(read_int // 16)

	for i in range(128):
		read_byte = packed.read(1)
		read_int = int.from_bytes(read_byte)
		table_0f.append(read_int % 16)
		table_0f.append(read_int // 16)

	last_0 = offsets[1]

	next_function = True
	function_table_position = 1
	functions_positions = []
	for i in range(256):
		functions_positions.append(0)

	while offsets[0] != last_0:
		next_int = read_from(0, packed)
		instr = next_int

		if next_function and not(next_int == 0xCC):
			functions_positions[function_table_position] = len(result)
			function_table_position += 1
			if function_table_position == 256:
				function_table_position = 1
			next_function = False

		if next_int == 0xCE:
			next_int = read_from(0, packed)
			result.append(next_int)
			continue
			
		result.append(next_int)

		operand_16_bit = False
		if next_int == 0x66:
			operand_16_bit = True
			next_int = read_from(0, packed)
			result.append(next_int)
			instr = next_int

		if next_int == 0xC2 or next_int == 0xC3:
			next_function = True

		if next_int == 0x0F:
			next_int = read_from(0, packed)
			result.append(next_int)
			instr = next_int
			table_value = table_0f[next_int]
		else:
			table_value = table_normal[next_int]

		if table_value & 2 == 2:				# MODRM
			next_int = read_from(0, packed)
			result.append(next_int)
			modrm = next_int

			if table_value & 3 == 3:			# MODRM + EXTRA OPCODE
				table_value = 2
				if modrm & 0x38 == 0:
					if instr & 8 == 0:
						table_value += 4

			only_mod_rm = modrm & 0xC7
			has_sib = only_mod_rm != 0xC4 and (only_mod_rm & 7) == 4
			if has_sib:	# SIB
				next_int = read_from(0, packed)
				result.append(next_int)
				sib_byte = next_int

			mod = only_mod_rm & 0xC0
			if mod == 0x40:
				rm = only_mod_rm & 7
				next_int = read_from(1 + rm, packed)
				result.append(next_int)

			if mod == 0x80 or only_mod_rm == 5 or (mod == 0 and has_sib and (sib_byte & 7) == 5):
				if only_mod_rm == 5:
					used_seg = 14
				else:
					used_seg = 13
				i1, i2, i3 = read_from(used_seg, packed), read_from(used_seg, packed), read_from(used_seg, packed)
				ih = read_from(18, packed)
				result.append(i1)
				result.append(i2)
				result.append(i3)
				result.append(ih)
 
		if table_value & 3 != 1:
			if table_value >= 4:
				if (table_value // 4) == 1:
					ih = read_from(10, packed)
					result.append(ih)
				elif ((table_value // 4)) == 2 and not(operand_16_bit):
					i1, i2, i3, i4 = read_from(12, packed), read_from(12, packed), read_from(12, packed), read_from(12, packed)
					result.append(i1)
					result.append(i2)
					result.append(i3)
					result.append(i4)
				else:
					i1, i2 = read_from(11, packed), read_from(11, packed)
					result.append(i1)
					result.append(i2)
		elif table_value >= 4:
			if (table_value // 4) == 1:
				ih = read_from(9, packed)
				result.append(ih)
			else:
				if result[-1] == 0xE8:
					ih = read_from(16, packed)
					if ih != 0:
						real_offset = functions_positions[ih]
						disp = real_offset - len(result) - 4
						store_dword(disp)
					else:
						i1, i2 = read_from(20, packed), read_from(20, packed)
						i3, i4 = read_from(16, packed), read_from(16, packed)
						t = 256 * 256 * 256 * i2 + 256 * 256 * i1 + 256 * i4 + i3

						functions_positions[function_table_position] = t
						function_table_position += 1
						if function_table_position == 256:
							function_table_position = 1

						disp = t - len(result) - 4
						store_dword(disp)
				else:
					i1, i2 = read_from(20, packed), read_from(20, packed)
					i3, i4 = read_from(17, packed), read_from(17, packed)
					t = 256 * 256 * 256 * i2 + 256 * 256 * i1 + 256 * i4 + i3
					disp = t // 2
					if t & 1:
						disp = (~disp) & 0xFFFFFFFF
					last_jmp = (last_jmp + disp) & 0xFFFFFFFF
					disp = last_jmp - len(result) - 4
					store_dword(disp)					
		else:
			i1, i2, i3 = read_from(15, packed), read_from(15, packed), read_from(15, packed)
			ih = read_from(19, packed)
			result.append(i1)
			result.append(i2)
			result.append(i3)
			result.append(ih)

	packed.seek(data_offset)
	while next_byte := packed.read(1):		
		next_int = int.from_bytes(next_byte)
		result.append(next_int)

with open('kkrunchy_unpacker_stage2.out', 'wb') as f:
        f.write(bytes(result))
