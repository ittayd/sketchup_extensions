# Copyright 2016 Trimble Navigation Limited
# Licensed under the MIT license

require 'sketchup.rb'
require 'set'

class Object
  def tap
    yield self
    self
  end
  
  def with_label(prefix = nil)
	"#{prefix.nil? ? '' : prefix + '='}#{self.inspect}"
  end
  
  def tputs(prefix = nil)
	puts with_label(prefix)
	self
  end
end

class Geom::Transformation
  def to_matrix(label = "", prefix = nil)
	prefix ||= label.length
	if prefix.is_a? Integer
		prefix = "%#{prefix}s" % ''
	end
    a = self.to_a
    f = "%8.3f"
    l = [f, f, f, f].join(" ") + "\n"
    str =  sprintf label + l,  a[0], a[1], a[2], a[3]
    str += sprintf prefix + l,  a[4], a[5], a[6], a[7]
    str += sprintf prefix + l,  a[8], a[9], a[10], a[11]
    str += sprintf prefix+ ("%8s %8s %8s " + f + "\n"),  a[12].to_l, a[13].to_l, a[14].to_l, a[15]
    str 
  end
end

class Geom::Point3d
	def to_lengths
		"(#{self.x.to_l}, #{self.y.to_l}, #{self.z.to_l})"
	end
end

module Ittay

	
	module InstanceEnhancements
		# def transformation2
			# undo = 0
			# selection = self.model.selection.map(&:itself)

			# begin 
				# while !self.model.active_path.nil? && self.model.active_path.include?(self) 
					# # this self is open. this causes sketchup to return the unit transformation for it, and parents while
					# # the edit_tranfrom is the comulative transform (to the model space)
					# self.model.close_active
					# undo += 1
				# end

				# t = self.transformation

				# if self.parent.entities == self.model.active_entities
					# # self belongs to the current/active entities collection.
					# # Here SketchUp for some reason transforms the coordinates to model space before returning it.
					# # Transform it back to the logical and consistent local coordinate space.
					# # Transformations and other coordinates (Point3d and Vector3d) requires different methods for applying transformations.
					# t = self.model.edit_transform.inverse * t
				# end
				# t 
			# ensure 
				# undo.times {Sketchup.undo}
				# selection.clear
				# self.model.selection.add(selection) 
			# end 
		# end
		
		# def model_transformations 
		
			# if self.parent.is_a?(Sketchup::DefinitionList) || self.parent.is_a?(Sketchup::Model)
				# return [self.transformation]
			# end
			# self.parent.instances.flat_map do |i| 
				# i.model_transformations
			# end.map do |ct| 
				# self.transformation * ct 
			# end.uniq
		# end
	end
end

class Sketchup::Group
	include Ittay::InstanceEnhancements
end

class Sketchup::ComponentInstance
	include Ittay::InstanceEnhancements
end



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
	
  module ScaledDimensions
	
	def filter(entities, hidden = false, arr = [])
		if not entities.nil?
		  entities.each do |entity|
			if hidden || (entity.visible? && entity.layer.visible?)
				case entity
					when Sketchup::DimensionLinear 
						arr.push(entity)
					when Sketchup::Group
						filter(entity.entities, hidden, arr)
					when Sketchup::ComponentInstance
						filter(entity.definition.entities, hidden, arr)
				end
			end
		  end
		end
		arr
	end
	
	def in_global_context(model, preserve_selection = true)
		selection = model.selection.map(&:itself) if preserve_selection

		model.start_operation("Dummy", true)
		begin 
			while !model.active_path.nil? 
				# this self is open. this causes sketchup to return the unit transformation for it, and parents while
				# the edit_tranfrom is the comulative transform (to the model space)
				model.close_active
			end

			yield
		ensure 
			model.abort_operation
			if preserve_selection
				model.selection.clear
				model.selection.add(selection) 
			end
		end 
			
	end
	
	PathTransformation ||= Struct.new(:path, :transformation)
	
	def model_path_transformations(instance)
		# doesn't account for cases when in an open group. use in_global_context to eliminate that
		if instance.parent.is_a?(Sketchup::DefinitionList) || instance.parent.is_a?(Sketchup::Model)
			return [PathTransformation.new([instance], instance.transformation)]
		end
		instance.parent.instances.flat_map do |i| 
			model_path_transformations(i)
		end.map do |pt| 
			PathTransformation.new(pt.path + [instance], pt.transformation  * instance.transformation)
		end.uniq
	end
	
	def model_transformations(instance)
		model_path_transformations(instance).map(&:transformation)
	end
	
	def parent_transformation(dim)
		# no support for dimensions inside components with more than 1 instance
		parent = dim.parent
		return Geom::Transformation.new if parent.is_a?(Sketchup::Model) 
		model_transformations(parent.instances[0])[0]
	end
	
	class ScaledDimensionsTool 
		include ScaledDimensions
		
		class SelectionObserver < Sketchup::SelectionObserver
			def initialize(tool)
				@tool = tool
			end
			
			def onSelectionBulkChange(selection)
				return if @suspend
				suspend
				@tool.onSelectionBulkChange(selection)
				resume
			end
			
			def onSelectionAdded(selection, entity)
				return if @suspend
				suspend
				selection.add(entity)
				@tool.onSelectionBulkChange(selection)
				resume
			end
			
			def suspend
				@suspend = true
			end
			
			def resume
				@suspend = false
			end
		end
		
		def selected_dims 
			@selected_dims_and_paths.map{|dim, ent| dim}
		end
		
		def selected_dims?
			!@selected_dims_and_paths.empty?
		end
		
		# def instances(ent, pos, ancestors = nil) 
			# if ent.tputs("ent").nil?
				# return []
			# end
			
			# if !ent.parent.is_a?(Sketchup::ComponentDefinition)
				# return []
			# end
			
			# ancestors ||= ent.parent.instances
			# ancestors.tputs("parent instances")

			# ancestors.find_all do |inst| # find any instances of the parent that contains the entity
				# model_transformations(inst).any? do |t| # the instance can appear in several parents (who are component definitions)
					# puts 
					# ent.position.transform(t) == pos
				# end
			# end.tputs('found').flat_map do |inst| # for each instance, recursively find the instances that contain it to create a path
				# recursion = if inst.parent.is_a?(Sketchup::ComponentDefinition)
					 # instances(ent, pos, inst.parent.instances)
				# else
					# []
				# end.tputs('recursion')
				# recursion << inst
			# end.tputs('flat_map')
		# end
		
		def instance_paths(ent, pos)
			if ent.nil?
				return []
			end
			if !ent.parent.is_a?(Sketchup::ComponentDefinition)
				return []
			end
			
			ent.parent.instances.flat_map do |inst|
				mpt = model_path_transformations(inst)
				mpt.map do |pt| 
					case ent
					when Sketchup::Vertex
						if ent.position.transform(pt.transformation) == pos
							pt.path
						end
					when Sketchup::Edge
						if pos.distance_to_line(ent.line.map{|x| x.transform(pt.transformation)}) == 0
							pt.path
						end
					else
						nil
					end
				end 
			end.compact.uniq
		end
		
		def partial_paths(paths)
			paths.flat_map do |path|
				Array.new(path.length) { |i| path[0..i] }
			end.uniq
		end
		
		def activate 
			selection = Sketchup.active_model.selection
			@pre_selected = selection.map(&:itself)
			only_dims = filter(selection)
			@selected_dims_and_paths = in_global_context(selection.model) do 
				only_dims.map do |dim|
				
					
					start_instances = instance_paths(dim.start[0], dim.start[1].transform(parent_transformation(dim)))
					end_instances = instance_paths(dim.end[0], dim.end[1].transform(parent_transformation(dim)))
					
					common_paths = start_instances.product(end_instances).map do |start_inst, end_inst| 
						start_inst & end_inst
					end.sort_by(&:length).reverse
					
					common_uniq = common_paths.inject([]) do |uniq, path|
						if uniq.empty?
							[path]
						else
							if uniq.last & path == path
								uniq
							else
								uniq + [path]
							end
						end
					end
					
					
					path = case common_uniq.size 
						when 0 
							puts 'Nothing common'
							nil
						when 1
							puts 'One common'
							common_uniq[0]
						else 
							puts 'Too many common'
							nil
					end
					[dim, path.nil? ? nil : Sketchup::InstancePath.new(path)]
				end
			end
				
			if (!selected_dims?)
				UI.messagebox("Please select dimensions or a group that contains dimensions")
				Sketchup.active_model.tools.pop_tool
				return
			end

			unassociated = @selected_dims_and_paths.count{|dim, ent| ent.nil?} 
			
			# if !no_ents.empty? && !with_ents.empty?
				
				# mode = UI.inputbox(["Mode"], [EXIT], [[EXIT, ONLY_ATTACHED, APPLY_TO_ALL].join("|")])
				# case mode
					# when EXIT
						# finish(selection.model, [])
						# return
					# when ONLY_ATTACHED
						# finish(selection.model, with_ents)
						# return

				# end
			# end
			
			selection.clear
			selection.add(selected_dims)
			
			Sketchup.set_status_text("#{unassociated} unassociated dimensions. Enter scale or select group to unscale by. Hit return to finish", SB_PROMPT)
			Sketchup.set_status_text("Scale", SB_VCB_LABEL)
			
			
			scale = selected_dims.inject(0) do |scale, dim| 
				dim_scale = dim.get_attribute('scaling', 'scale')
				if (not dim_scale.nil?) 
					dim_scale = dim_scale.to_f
					case scale
						when 0
							scale = dim_scale
						when dim_scale
							;
						else
							scale = -1
					end
				end
				scale

			end
			if scale > 0
				Sketchup.set_status_text(scale, SB_VCB_VALUE)
			end

			@selection_observer = SelectionObserver.new(self)
			selection.add_observer(@selection_observer)

		end
		
		def deactivate(view)
			view.model.selection.remove_observer(@selection_observer)
		end
		
		def onSelectionBulkChange(selection)
			if (selection.count == 1)
				# assuming seleciton in the outliner
				if (!select(selection[0])) 
					selection.clear
				end
				
			end
			selection.add(selected_dims)
		end	
		
		def enableVCB?
			return true
		end
		
		def onLButtonDown(flags, x, y, view)
			ph = view.pick_helper
			ph.do_pick(x, y)
			bp = ph.best_picked
			select(bp)

		end
		
		def select(entity) 
			if (is_supported(entity))
				@selected = entity
				Sketchup.set_status_text("Reverse scaling by #{entity.name}. Press return to finish", SB_PROMPT)
				true
			else 
				false
			end
		end
		
		def finish(view, override = nil)
			# TODO? add undo with model observer
			model = view.model
			model.start_operation('Scale Dimensions', true)
			@selected_dims_and_paths.each do |dim, scale| 
				scale = override unless override.nil?
				dim.delete_attribute('scaling')
				# dim.set_attribute('scaling', 'parent_scale', parent_scale(dim).to_a)
				case scale
					when Numeric
						dim.set_attribute('scaling', 'scale', scale)
					else  # path, Array
						#if is_supported(scale)
						# there's a but in sketchup where InstancePath#persistent_id_path would not return the id of the leaf
						persistent_id_path = scale.to_a.map(&:persistent_id).join('.')
						dim.set_attribute('scaling', 'persistent_id', persistent_id_path)
						#end

				end
				Ittay::ScaledDimensions.start_updating(dim)
			end
			model.commit_operation
			# Ittay::ScaledDimensions.init_timer
			Ittay::ScaledDimensions.update_scaled_dims(selected_dims)
			
			selection = model.selection
			selection.clear
			selection.add(@pre_selected)

			Sketchup.active_model.tools.pop_tool

		end
		
		def onUserText(text, view)
			begin
				scale = Float(text)
				if (scale <= 0) then raise "not positive" end
			rescue
				# Error parsing the text
				UI.beep
				puts "Cannot convert #{text} to a scale number"
				scale = nil
				Sketchup::set_status_text "", SB_VCB_VALUE
			end
			return if !scale
			
			finish(view, scale)
		end
		
		def onMouseMove(flags, x, y, view)
			ph = view.pick_helper
			ph.do_pick(x, y)
			bp = ph.best_picked
			selection = view.model.selection
			if (@bp != bp)
				selection.remove(@bp) unless @bp.nil?
				
				if (is_supported(bp)) 
					@bp = bp
				
					view.model.selection.add(bp)
				end

				view.invalidate
			end
		end
		
	    def onLButtonUp(flags, x, y, view)
		end

		def is_supported(entity)
			Sketchup::Entity === entity and not (Sketchup::Axes === entity) and entity.respond_to?(:transformation)
		end
		
		def draw(view)
		end
		
		def onReturn(view)
			finish(view, @selected) 
		end
		
		def onKeyDown(key, repeat, flags, view)			
		end
		
		def onKeyUp(key, repeat, flags, view)
		end
		
		def suspend(view) 
			puts 'suspend'
		end
		
		def resume(view)
			puts 'resume'
		end
	end

	extend ScaledDimensions
  
	def self.scale_dimensions

      # We need a reference to the currently active model. The SketchUp API
      # currently only let you work on the active model. Under Windows there
      # will be only one model open at a time, but under OS X there might be
      # multiple models open.
      # 
      # Beware that if there is no model open under OS X then `active_model`
      # will return nil. In this example we ignore that for simplicity.
      model = Sketchup.active_model

      # Whenever you make changes to the model you must take care to use
      # `model.start_operation` and `model.commit_operation` to wrap everything
      # into a single undo step. Otherwise the user risk not being able to undo
      # everything and loose work.
      # 
      # Making sure your model changes is undoable in a single undo step is a
      # requirement of the Extension Warehouse submission quality checks.
      # 
      # Note that the first argument name is a string that will be appended to
      # the Edit > Undo menu - so make sure you name your operations something
      # the users can understand.
  	 
      model.start_operation('Create Scaled Dim', true)

	  scale = scale_dialog()
	  
	  model.selection.grep(Sketchup::DimensionLinear).each do |dim|
		puts "Scaling #{dim}" if @debug
	    dim.set_attribute('scaling', 'scale', scale)
		# dim.set_attribute('scaling', 'parent_scale', dim.parent.bounds.diagonal)
		
		start_updating(dim)
	  end
	  
	  self.init_timer
	  
      # Finally we are done and we close the operation. In production you will
      # want to catch errors and abort to clean up if your function failed.
      # But for simplicity we won't do this here.
      model.commit_operation
    end
	
	def self.scaled_dims 
		@scaled_dims ||= []
	end
	
	def self.start_updating(dim) 
		scaled_dims.push(dim)
	end 
	
	def self.debug=(enable)
		@debug = enable
	end
	
	
	def self.scale_dim(dim, scaling, debug = @debug)	
	def format_trans(name, trans)
			"#{trans.is_a?(Geom::Transformation) ? trans.to_matrix("#{name}=") : trans}"
		end
		def format_point(point)
			"(#{point.x.to_l.to_s}, #{point.y.to_l.to_s}, #{point.z.to_l.to_s})"
		end
		def format_points(name, points)
			"#{name}=[start=#{format_point(points[0])}, end=#{format_point(points[1])}, offset=#{format_point(points[2])}]"
		end
		def transform(arr, transformation)
			arr.map{|e| e.transform(transformation)}
		end
		points = [dim.start[1], dim.end[1], dim.offset_vector]
		normalized = transform(points, parent_transformation(dim))
		transformed = transform(normalized, scaling).tputs('transformed2')
		scaled = transformed[0].distance_to_line([transformed[1], transformed[2]]).to_f.to_l #for some reason, distance_to_line returns in inches
		
		puts "#{dim}:\n#{format_points('orig', points)}\n#{format_trans('parent_transformation', parent_transformation(dim))}\n#{format_points('normalized', normalized)}\n#{format_points('transformed', transformed)}\n#{format_trans('scaling', scaling)}\n#{scaled}"  if debug
		scaled
	end
	
	def self.update_scaled_dims(dims = nil)
		model = Sketchup.active_model
		dims ||= get_scaled_dims(model.selection.empty? ? nil : model.selection)
 
		scaled = in_global_context(model) do 
			dims.map do |dim|
				# Sketchup has a bug in which dimensions for scaled groups return text that is different than what actually is displayed. So can't rely on dim.text
				# current = dim.text
				# current = dim.get_attribute('scaling', 'text')
				scale_str = dim.get_attribute('scaling', 'scale')
				persistent_id = dim.get_attribute('scaling', 'persistent_id')
				scaling = if not scale_str.nil? 
					Geom::Transformation.scaling(scale_str.to_f)
				elsif not persistent_id.nil?
					path = model.instance_path_from_pid_path(persistent_id)
					path.transformation.inverse
				else	
					raise 'no scale or persistent id attributes'
				end
				scaled = scale_dim(dim, scaling)
				scaled = scaled.to_s.sub('~ ', '')
				[dim, scaled] 
			end.compact
		end
		
		if scaled.any? 
			model.start_operation('Update Scaled Dim', true)
			something = false
			scaled.each do |dim, scaled|
				# If the dimension is of a scaled group, say by 2, and the dimension says 10, then the dim.text method may return 5 (dimension before scale)
				# so if I scale the dimension, the scale is 5, but setting the text to 5 will make SU think nothing changed, so won't update the text property
				# and the dimension will still show 10.
				before = dim.text
				dim.text = ''
				default = before == dim.text
				dim.text = before
				if default || before != scaled
					dim.text = 'bug' 
					dim.text = scaled
					dim.set_attribute('scaling', 'text', scaled)
					something = true
				end
			end
			something ? model.commit_operation : model.abort_operation

		end
		model.selection.add()
	end
	
	def self.get_scaled_dims(ents = nil)
		model = Sketchup.active_model
	  
		filter(ents || model.entities, true).select do |dim|
			dim.attribute_dictionary('scaling')
		end
	end
	
	def self.init_scaled_dims
		scaled_dims = get_scaled_dims
		update_scaled_dims(scaled_dims)
	end
	
	def self.stop_timer
		UI.stop_timer(@timer)
		@timer = nil
	end
	
	def self.init_timer 
	  @timer ||= UI.start_timer(3, true) do 
		begin
			if model.tools.active_tool_id == 21022
		
				scaled_dims.delete_if do |dim|
					dim.deleted? || dim.attribute_dictionary('scaling').nil?
				end

				self.update_scaled_dims(scaled_dims)
			end
		rescue 
			stop_timer
			raise 
		end
	  end
	end
	
	def get_dim_and_edge
		ss = Sketchup.active_model.selection
		dim = ss.find{|e| e.class == Sketchup::DimensionLinear}
		edge = ss.find{|e| e.class == Sketchup::Edge}
		[dim, edge]
	end
	
	def self.offset_dim_by_edge
		dim, edge = get_dim_and_edge
		
		dim.offset_vector = edge.line[1]
	end

	
	
    # Here we add a menu item for the extension. Note that we again use a
    # load guard to prevent multiple menu items from accidentally being
    # created.
	
    unless file_loaded?(__FILE__)
	  
	  self.init_scaled_dims

	  
 	  Ittay.register_command(UI::Command.new('Offset Dimension by Edge') {self.offset_dim_by_edge}) do |selection|
		dim, edge = get_dim_and_edge unless selection.length != 2
		!dim.nil? && !edge.nil?
	  end
	  
	  Ittay.register_command(UI::Command.new('Scale Dimensions') {Sketchup.active_model.tools.push_tool(ScaledDimensionsTool.new)})
	  
	  Ittay.register_command(UI::Command.new('Update Dimensions') {update_scaled_dims(get_scaled_dims)})	  

      file_loaded(__FILE__)
    end

  end # module 
end # module 
