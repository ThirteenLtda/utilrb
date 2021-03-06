require 'utilrb/test'
require 'flexmock/minitest'
require 'tempfile'

require 'utilrb/kernel'

class TC_Kernel < Minitest::Test
    # Do NOT move this block. Some tests are checking the error lines in the
    # backtraces
    DSL_EXEC_BLOCK = Proc.new do
        real_method
        if KnownConstant != 10
            raise ArgumentError, "invalid constant value"
        end
        class Submod::Klass
            def my_method
            end
        end
        name('test')
        unknown_method()
    end

    def test_validate_options_passes_options_unmodified_if_they_are_valid_and_there_is_no_additional_defaults
        options = { :a => 1, :c => 2 }
        assert_equal options, validate_options(options, :a, :b, :c)
    end

    def test_validate_options_accepts_a_list_of_valid_options_as_array
        options = { :a => 1, :c => 2 }
        assert_equal options, validate_options(options, [:a, :b, :c])
    end

    def test_validate_options_raises_ArgumentError_if_given_an_unknown_option
        assert_raises(ArgumentError) { validate_options(Hash[c: 10], :b) }
    end

    def test_validate_options_does_not_add_options_without_default_to_the_returned_value
        assert_equal Hash.new, validate_options(Hash.new, :a, :b, :c)
    end

    def test_validate_options_sets_defaults
        assert_equal Hash[c: 10], validate_options(Hash.new, c: 10)
    end

    def test_validate_options_does_not_override_nil_by_the_default_value
        assert_equal Hash[c: nil], validate_options(Hash[c: nil], c: 10)
    end

    def test_validate_options_does_take_false_as_default_value
        assert_equal Hash[c: false], validate_options(Hash.new, c: false)
    end

    def test_validate_options_does_not_take_nil_as_a_default_value
        assert_equal Hash.new, validate_options(Hash.new, c: nil)
    end

    def test_validate_options_can_handle_string_keys
        assert_equal Hash[a: 10, c: nil], validate_options(Hash['c' => nil], 'a' => 10, :c =>  10)
    end

    def test_filter_options_filters_keys_that_have_a_nil_value
        assert_equal [Hash[c: 10], Hash.new], filter_options(Hash[c: 10], c: nil)
    end

    def test_with_module
        obj = Object.new
        c0, c1 = nil
        mod0 = Module.new do
            const_set(:Const, c0 = Object.new)
        end
        mod1 = Module.new do
            const_set(:Const, c1 = Object.new)
        end

        eval_string = "Const"
        const_val = obj.with_module(mod0, mod1, eval_string)
        assert_equal(c0, const_val)
        const_val = obj.with_module(mod1, mod0, eval_string)
        assert_equal(c1, const_val)

        const_val = obj.with_module(mod0, mod1) { Const }
        assert_equal(c0, const_val)
        const_val = obj.with_module(mod1, mod0) { Const }
        assert_equal(c1, const_val)

        assert_raises(NameError) { Const  }
    end

    module Mod
        module Submod
            class Klass
            end
        end

        const_set(:KnownConstant, 10)
    end

    def test_eval_dsl_file
        obj = Class.new do
            def real_method_called?; !!@real_method_called end
            def name(value)
            end
            def real_method
                @real_method_called = true
            end
        end.new

        Tempfile.open('test_eval_dsl_file') do |io|
            io.puts <<-EOD
            real_method
            if KnownConstant != 10
                raise ArgumentError, "invalid constant value"
            end
            class Submod::Klass
                def my_method
                end
            end
            name('test')
            unknown_method()
            EOD
            io.flush

            begin
                eval_dsl_file(io.path, obj, [], false)
                assert(obj.real_method_called?, "the block has not been evaluated")
                flunk("did not raise NameError for KnownConstant")
            rescue NameError => e
                assert e.message =~ /KnownConstant/, e.message
                assert e.backtrace.first =~ /#{io.path}:2/, "wrong backtrace when checking constant resolution: #{e.backtrace.join("\n")}"
            end

            begin
                eval_dsl_file(io.path, obj, [Mod], false)
                flunk("did not raise NoMethodError for unknown_method")
            rescue NoMethodError => e
                assert e.message =~ /unknown_method/
                assert e.backtrace.first =~ /#{io.path}:10/, "wrong backtrace when checking method resolution: #{e.backtrace.join("\n")}"
            end

            # instance_methods returns strings on 1.8 and symbols on 1.9. Conver
            # to strings to have the right assertion on both
            methods = Mod::Submod::Klass.instance_methods(false).map(&:to_s)
            assert(methods.include?('my_method'), "the 'class K' statement did not refer to the already defined class")
        end
    end

    def test_dsl_exec
        obj = Class.new do
            def real_method_called?; !!@real_method_called end
            def name(value)
            end
            def real_method
                @real_method_called = true
            end
        end.new

        begin
            dsl_exec(obj, [], false, &DSL_EXEC_BLOCK)
            assert(obj.real_method_called?, "the block has not been evaluated")
            flunk("did not raise NameError for KnownConstant")
        rescue NameError => e
            assert e.message =~ /KnownConstant/, e.message
            expected = "test_kernel.rb:12"
            assert e.backtrace.first =~ /#{expected}/, "wrong backtrace when checking constant resolution: #{e.backtrace.join("\n")}, expected #{expected}"
        end

        begin
            dsl_exec(obj, [Mod], false, &DSL_EXEC_BLOCK)
            flunk("did not raise NoMethodError for unknown_method")
        rescue NoMethodError => e
            assert e.message =~ /unknown_method/
            expected = "test_kernel.rb:20"
            assert e.backtrace.first =~ /#{expected}/, "wrong backtrace when checking method resolution: #{e.backtrace[0]}, expected #{expected}"
        end

        # instance_methods returns strings on 1.8 and symbols on 1.9. Conver
        # to strings to have the right assertion on both
        methods = Mod::Submod::Klass.instance_methods(false).map(&:to_s)
        assert(methods.include?('my_method'), "the 'class K' statement did not refer to the already defined class")
    end

    def test_load_dsl_file_loaded_features_behaviour
        eval_context = Class.new do
            attr_reader :real_method_call_count
            def initialize
                @real_method_call_count = 0
            end
            def real_method
                @real_method_call_count += 1
            end
        end

        Tempfile.open('test_eval_dsl_file') do |io|
            io.puts <<-EOD
            real_method
            EOD
            io.flush

            obj = eval_context.new
            assert(Kernel.load_dsl_file(io.path, obj, [], false))
            assert_equal(1, obj.real_method_call_count)
            assert($LOADED_FEATURES.include?(io.path))
            assert(!Kernel.load_dsl_file(io.path, obj, [], false))
            assert_equal(1, obj.real_method_call_count)

            $LOADED_FEATURES.delete(io.path)
        end

        Tempfile.open('test_eval_dsl_file') do |io|
            io.puts <<-EOD
            raise
            EOD
            io.flush

            obj = eval_context.new
            assert(!$LOADED_FEATURES.include?(io.path))
            assert_raises(RuntimeError) { Kernel.load_dsl_file(io.path, obj, [], false) }
            assert(!$LOADED_FEATURES.include?(io.path))
            assert_equal(0, obj.real_method_call_count)
        end
    end

    def test_poll
        flexmock(Kernel).should_receive(:sleep).with(2).twice
        counter = 0
        Kernel.poll(2) do
            counter += 1
            if counter > 2
                break
            end
        end
    end

    def test_wait_until
        flexmock(Kernel).should_receive(:sleep).with(2).twice
        counter = 0
        Kernel.wait_until(2) do
            counter += 1
            counter > 2
        end
    end

    def test_wait_while
        flexmock(Kernel).should_receive(:sleep).with(2).twice
        counter = 0
        Kernel.wait_while(2) do
            counter += 1
            counter <= 2
        end
    end
end

describe "Kernel extensions" do
    describe "#check_arity" do
        def assert_arity_check(obj, *args, strict: nil)
            test_obj = nil
            if strict
                Class.new(Object) do
                    test_obj = method(:test, &obj)
                end
            else
                test_obj = obj
            end

            begin
                check_arity(obj, args.size, strict: strict)
            rescue ArgumentError
                begin
                    test_obj.call(*args)
                    flunk("#check_arity(_, #{args.size}) raised but #call passed")
                rescue ArgumentError
                    return false
                end
            end

            begin test_obj.call(*args)
            rescue ArgumentError => e
                flunk("#check_arity(_, #{args.size}) passed but #call failed with #{e.message}")
            end
            true
        end

        def assert_arity_check_succeeds(obj, *args, strict: nil)
            assert assert_arity_check(obj, *args, strict: strict), "arity check was expected to pass, but failed"
        end

        def assert_arity_check_fails(obj, *args, strict: nil)
            refute assert_arity_check(obj, *args, strict: strict), "arity check was expected to fail, but succeeded"
        end

        describe "of methods" do
            attr_reader :object
            before do
                @object = Class.new do
                    def arity_1(a); end
                    def arity_any(*a); end
                    def arity_1_more(a, *b); end
                end.new
            end

            it "passes if the method accepts the exact number of arguments" do
                assert_arity_check_succeeds(object.method(:arity_1), 1)
            end

            it "passes if the method accepts the requested number of arguments through a splat" do
                assert_arity_check_succeeds(object.method(:arity_any), 1)
                assert_arity_check_succeeds(object.method(:arity_1_more), 1)
            end

            it "raises if the method requires more arguments than requested" do
                assert_arity_check_fails(object.method(:arity_1_more))
            end

            it "raises if the method cannot accept as many arguments as requested" do
                assert_arity_check_fails(object.method(:arity_1), 1, 2)
            end
        end

        describe "of procs" do
            it "accepts more arguments than declared by the proc" do
                assert_arity_check_succeeds(proc { }, 1, 2)
                assert_arity_check_succeeds(proc { |a| }, 1, 2)
            end

            it "passes if the proc requires more arguments than requested" do
                assert_arity_check_succeeds(proc { |a, b| }, 1)
            end

            it "is evaluated using strict (method) rules if the strict argument is given as true" do
                assert_arity_check_fails(proc { |a| }, 1, 2, strict: true)
            end
        end

        describe "of lambdas" do
            it "does not accept more arguments than declared by the lambda" do
                assert_arity_check_fails(lambda { }, 1, 2)
                assert_arity_check_fails(lambda { |a| }, 1, 2)
            end

            it "passes if given less arguments than expected by the lambda" do
                assert_arity_check_fails(lambda { |a, b| }, 1)
            end

            it "is evaluated using strict (method) rules if the strict argument is given as true" do
                assert_arity_check_fails(lambda { |a| }, 1, 2, strict: true)
            end
        end
    end
end



