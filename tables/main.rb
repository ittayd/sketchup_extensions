# Copyright 2016 Trimble Navigation Limited
# Licensed under the MIT license

require 'sketchup.rb'
require 'set'


module Ittay
	CommandWrapper ||= Struct.new(:command, :appear)
	def self.add_submenu(menu)
		menu.add_submenu("Ittay's")
	end	
		
	def self.register_command(command, &block)
 		@submenuenu ||= add_submenu(UI.menu('Plugins'))
		begin
			@submenuenu.add_item(command)
		rescue Exception => e 
			puts "exception @{e.inspect}"
			@submenuenu = UI.menu('Plugins').add_submenu("Ittay's")
			@submenuenu.add_item(command)
		end
		
		@handlers_count ||= UI.add_context_menu_handler(&(method(:handle_context_menu)))
		@commands ||= []
		
		@commands.push(CommandWrapper.new(command, block))
	end
	
	def self.handle_context_menu(menu)
		model = Sketchup.active_model
		menu = add_submenu(menu)
		@commands.each do |cw|
			if cw.appear.nil? || cw.appear.call(model.selection)
				menu.add_item(cw.command)
			end
		end
	end
	
  Token ||= Struct.new(:characters, :type)

  def self.add_or_new(tokens, ch, type)
		if !tokens.empty? && tokens.last.type == type
			tokens.last.characters.push(ch)
		else 
			tokens.push(Token.new([ch], type))
		end
  end
  def self.to_visual(str)
	str.each_char.inject([]) do |tokens, ch| 
		case ch
			when /[ -."']/
				tokens.push(Token.new([ch], :separator))
			when /\p{Hebrew}/
				add_or_new(tokens, ch, :hebrew)
			else
				add_or_new(tokens, ch, :english)
		end
		tokens
	end.reverse.map do |token|
		if token.type == :hebrew
			token.characters.reverse!	
		end
		token.characters.join
	end.join
	
  end
  
  
  module Tables
	class TableDialog < UI::HtmlDialog
		def initialize(tool)
			puts 'init'
			super ({  
				:dialog_title => "Table text"
			})
			
			@base_dir = File.dirname(__FILE__)
			ui_loc = File.join( @base_dir , "ui.html" )
			set_file( ui_loc )
			
			add_action_callback("render") do |context, tsv, height, margins|#, hebrew|
				tool.render(tsv, height, margins)#, hebrew)
			end
			
			add_action_callback("onload") do |context|
				set_values(@tsv, @height, @margins)#, @hebrew)
			end
		end
		
		def set_values(tsv, height, margins)#, hebrew)
			@tsv = tsv || ''
			@height = height || '12mm'
			@margins = margins || '3mm'
			#@hebrew = hebrew || true
			execute_script("set_values(#{tsv.inspect}, #{height.inspect}, #{margins.inspect})")#, #{hebrew})".tputs('exec'))
		end
		
	end
	
	class TableTool
		@@defname ||= "TableComponent"

		class DefSpy < Sketchup::DefinitionObserver
			def onComponentInstanceAdded(definition, instance)
				definition.remove_observer(self)
				UI.start_timer(0.1,false) {
					TableTool.remove_definition(definition, instance)
				}
			end
		end

		Cell ||= Struct.new(:group, :origin, :height, :width)
		def initialize(model)
			@model = model
		end
		
		def activate
			@dlg = TableDialog.new(self)
			
			selection = @model.selection
			@dlg.show 
			
			if selection.length == 1 && selection[0].is_a?(Sketchup::Group) 
				tsv = selection[0].get_attribute('table', 'tsv')
				unless tsv.nil?
					@container = selection[0] 
					@dlg.set_values(tsv, @container.get_attribute('table', 'height'), @container.get_attribute('table', 'margins'))#, @container.get_attribute('table', 'hebrew')) 
				end
			end
			
			# @drawn = false
		    # @current_ip = Sketchup::InputPoint.new
			# @previous_ip = Sketchup::InputPoint.new

			
		end
		
		def deactivate(view)
			view.invalidate if @drawn
		end
		
		def render(tsv, text_height, margins)#, hebrew)
			hebrew = /^\p{hebrew}/ === tsv[0]
			table = tsv.split("\n").map do |line| 
				row = line.split("\t")
				row.reverse! if hebrew
				row
			end
			
			@model.start_operation("Draw table", true, true)
			
			place = false
			cdef = nil
			if @container.nil? || @container.deleted? 
				cdef = @model.definitions[@@defname]
				if cdef
					cdef.entities.clear! if cdef.entities.size > 0     
				else
					cdef = @model.definitions.add(@@defname)
       
				end
				@container = cdef.entities.add_group()
				@container.transform!(Geom::Transformation.new(Geom::Point3d.new(0,0,0), Geom::Vector3d.new(1,0,0), Math::PI/2))
			end
			
			@container.entities.erase_entities(@container.entities.map(&:itself))

			@container.set_attribute('table', 'height', text_height)
			@container.set_attribute('table', 'margins', margins)
			#@container.set_attribute('table', 'hebrew', hebrew)
			

			text_height = Sketchup.parse_length(text_height)
			margins = Sketchup.parse_length(margins)
			
			def add_text(group, text, text_height)
				group.entities.add_3d_text(text, TextAlignLeft, "Arial", false, false, text_height, 0.0, 0.0, true, 0.0)
				group.material = "black"
				group
			end
							
			table = table.map do |row|
				row.map do |cell|
					textg = @container.entities.add_group
					# hack around sketchup not providing a way to set the baseline (y) for the text
					cell = Ittay.to_visual(cell) if /^\p{hebrew}/ === cell[0] 
					add_text(textg, "|" + cell, text_height)
				
					
					height = textg.bounds.height
										
					origin = textg.bounds.corner(0) # the origin of the text inside the group
					
					pipe_edges = textg.entities.take(4)
					textg.entities.erase_entities(pipe_edges)
					
					origin.x = textg.bounds.corner(0).x #preserve y, in case sketchup starts rendering text above the origin (as it does for x)
					
					width = textg.bounds.width

					origin.x -= margins
					origin.y -= margins
					height += 2 * margins
					width += 2 * margins
					
					Cell.new(textg, origin, height, width)
				end
			end
			
			max_widths = table.inject([]) do |max, row| 
				row.each_with_index do |cell, i| 
					width = cell.width
					max[i] = width if max[i].nil? || width > max[i] 
				end
				max
			end
				
			max_heights = table.map do |row|
				row.map(&:height).max
			end
			
			table.each do |row|
				row.fill(row.length, (max_widths.length - row.length)) do |i|
					filler = @container.entities.add_group
					filler.entities.add_cpoint(Geom::Point3d.new(0,0,0))
					Cell.new(filler, Geom::Point3d.new(0,0,0), 0, 0)
				end
			end
			
			table.each_with_index.map do |row, i|
				y = max_heights.drop(i+1).inject(0){|sum,x| sum + x }
				height = max_heights[i]
				row.each_with_index.map do |cell, j|
					x = max_widths.take(j).inject(0){|sum,x| sum + x }
					width = max_widths[j]
					offset = hebrew ? cell.width - width : 0
					origin = Geom::Transformation.new(cell.origin) 
					trans = origin.inverse * Geom::Transformation.new(Geom::Point3d.new(x - offset, y, 0))
					frame = [Geom::Point3d.new(offset,0,0), Geom::Point3d.new(offset, height, 0), Geom::Point3d.new(offset + width, height, 0), Geom::Point3d.new(offset + width, 0, 0), Geom::Point3d.new(offset,0,0)].map{|p| p.transform(origin)}
					cell.group.entities.add_edges frame
					cell.group.move!(trans)
					
				end
			end
			
			@container.set_attribute('table', 'tsv', tsv)
			
			@model.commit_operation
			unless cdef.nil?
				cdef.add_observer(DefSpy::new)
				@model.place_component(cdef)
			end
		end
		
		 def self.remove_definition(definition, instance)
    #
			model = definition.model
			model.start_operation(@@defname,true,false,true)
			#
			instance.explode rescue nil
			definition.entities.clear! rescue nil
			#
			model.commit_operation
    #
		end ###
		
		# def onMouseMove(flags, x, y, view)
			# @current_ip.pick view, x, y
			# if( @current_ip != @previous_ip )
				# # if the point has changed from the last one we got, then
				# # see if we need to display the point.  We need to display it
				# # if it has a display representation or if the previous point
				# # was displayed.  The invalidate method on the view is used
				# # to tell the view that something has changed so that you need
				# # to refresh the view.
				# view.invalidate if( @current_ip.display? or @previous_ip.display? )
				# @previous_ip.copy! @current_ip
				
				# # set the tooltip that should be displayed to this point
				# view.tooltip = @previous_ip.tooltip
			# end
		# end

		# # The onLButtonDOwn method is called when the user presses the left mouse button.
		# def onLButtonDown(flags, x, y, view)
			# @current_ip.pick view, x, y
			# if( @current_ip.valid? )
				# @xdown = x
				# @ydown = y
				# @dlg.show
			# end
		# end
		
		# def draw(view)
			# if( @previous_ip.valid? && @previous_ip.display? )
				# @previous_ip.draw(view)
				# @drawn = true
			# end
		# end


	end 
	

	
	
    # Here we add a menu item for the extension. Note that we again use a
    # load guard to prevent multiple menu items from accidentally being
    # created.
	
    unless file_loaded?(__FILE__)	
		cmd = UI::Command.new("Edit Table") do 
			model = Sketchup.active_model
			model.tools.push_tool(TableTool.new(model)) 
		end
	  
		Ittay.register_command(cmd) do |selection|
			selection.length == 1 && selection[0].is_a?(Sketchup::Group) && !selection[0].attribute_dictionary('table').nil?
		end 
		file_loaded(__FILE__)
    end

  end # module 
end # module 
